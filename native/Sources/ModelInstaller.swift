import CryptoKit
import Foundation
import Moonshine

private struct ModelDependencyManifest: Decodable {
    struct Group: Decodable { let files: [File] }
    struct File: Decodable {
        let name: String
        let url: URL
        let size: Int64?
        let checksum: String
        let checksumType: String

        enum CodingKeys: String, CodingKey {
            case name, url, size, checksum
            case checksumType = "checksum_type"
        }
    }
    let groups: [Group]
}

enum MoonshineCatalog {
    static func englishMediumStreamingFiles() throws -> [ModelAsset] {
        var output: UnsafeMutablePointer<CChar>?
        let result = "en".withCString { language in
            "model_arch".withCString { optionName in
                "5".withCString { optionValue in
                    var option = moonshine_option_t(name: optionName, value: optionValue)
                    return moonshine_get_stt_dependencies(language, &option, 1, &output)
                }
            }
        }
        guard result == 0, let output else {
            let detail = String(cString: moonshine_error_to_string(result))
            throw NativeError.unavailable("Moonshine could not provide the English Medium Streaming model catalog. \(detail)")
        }
        defer { free(output) }

        let data = Data(bytes: output, count: strlen(output))
        let manifest = try JSONDecoder().decode(ModelDependencyManifest.self, from: data)
        guard let group = manifest.groups.first, !group.files.isEmpty else {
            throw NativeError.unavailable("Moonshine returned an empty model catalog.")
        }
        return try group.files.map { file in
            guard !file.name.isEmpty, URL(fileURLWithPath: file.name).lastPathComponent == file.name,
                  file.url.scheme == "https", file.url.host == "download.moonshine.ai" else {
                throw NativeError.unavailable("Moonshine returned an unsafe model file location.")
            }
            return ModelAsset(
                name: file.name, url: file.url.absoluteString, size: file.size,
                checksum: file.checksum, checksumType: file.checksumType
            )
        }
    }
}

final class ModelInstaller: @unchecked Sendable {
    private static let installLock = NSLock()
    let modelDirectory: URL
    private let modelID: SpeechModelID
    private let whisperVariant: WhisperModelVariant
    private let fileManager = FileManager.default

    init(modelDirectory: URL, modelID: SpeechModelID = .moonshine, whisperVariant: WhisperModelVariant = .largeV3Turbo) {
        self.modelDirectory = modelDirectory.standardizedFileURL
        self.modelID = modelID
        self.whisperVariant = whisperVariant
    }

    func verifyCachedModel(verifyChecksums: Bool = true) throws -> Bool {
        let files = try SpeechModelCatalog.assets(for: modelID, whisperVariant: whisperVariant)
        if fileManager.fileExists(atPath: modelDirectory.path), (try? Self.verify(files, in: modelDirectory, verifyChecksums: verifyChecksums)) != nil {
            Self.removeStaleBackups(for: modelDirectory, fileManager: fileManager)
            return true
        }
        guard let backup = Self.previousDirectories(for: modelDirectory, fileManager: fileManager)
            .first(where: { (try? Self.verify(files, in: $0, verifyChecksums: verifyChecksums)) != nil }) else {
            if fileManager.fileExists(atPath: modelDirectory.path) {
                throw NativeError.unavailable("The speech model download is incomplete or damaged. Download it again to repair it.")
            }
            return false
        }
        if fileManager.fileExists(atPath: modelDirectory.path) { try fileManager.removeItem(at: modelDirectory) }
        try fileManager.moveItem(at: backup, to: modelDirectory)
        Self.removeStaleBackups(for: modelDirectory, fileManager: fileManager)
        return true
    }

    func download(
        onProgress: @escaping @Sendable (_ file: String, _ fraction: Double) -> Void
    ) async throws {
        let files = try SpeechModelCatalog.assets(for: modelID, whisperVariant: whisperVariant)
        guard !files.isEmpty else { throw NativeError.unavailable("The selected speech model has no downloadable files.") }

        let parent = modelDirectory.deletingLastPathComponent()
        try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
        let attempt = UUID().uuidString
        let staging = parent.appendingPathComponent(".\(modelDirectory.lastPathComponent).download-\(attempt)", isDirectory: true)
        let backup = parent.appendingPathComponent(".\(modelDirectory.lastPathComponent).previous-\(attempt)", isDirectory: true)
        try fileManager.createDirectory(at: staging, withIntermediateDirectories: true)

        do {
            let totalSize = max(1, files.reduce(Int64(0)) { $0 + max(0, $1.size ?? 0) })
            var completedSize: Int64 = 0
            for file in files {
                try Task.checkCancellation()
                guard Self.isSafeRelativePath(file.name),
                      let url = URL(string: file.urlString), url.scheme == "https",
                      let host = url.host,
                      ["download.moonshine.ai", "huggingface.co"].contains(host) else {
                    throw NativeError.unavailable("The model catalog contains an unsafe download location.")
                }
                let destination = file.name.split(separator: "/").reduce(staging) {
                    $0.appendingPathComponent(String($1), isDirectory: false)
                }
                try fileManager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                let completedBeforeFile = completedSize
                let fileSize = file.size ?? 1
                let downloader = ModelFileDownload { fraction in
                    let currentSize = Int64(Double(fileSize) * fraction)
                    onProgress(file.name, min(0.99, Double(completedBeforeFile + currentSize) / Double(totalSize)))
                }
                try await downloader.download(url, to: destination)
                try Self.verify(file, at: destination)
                completedSize += fileSize
                onProgress(file.name, min(0.99, Double(completedSize) / Double(totalSize)))
            }
            try Task.checkCancellation()
            try Self.install(staging: staging, destination: modelDirectory, backup: backup, fileManager: fileManager)
            onProgress(files.last?.name ?? "model", 1)
        } catch {
            try? fileManager.removeItem(at: staging)
            throw error
        }
    }

    private static func verify(_ file: ModelAsset, at url: URL, verifyChecksum: Bool = true) throws {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let actualSize = (attributes[.size] as? NSNumber)?.int64Value
        if let expectedSize = file.size, actualSize != expectedSize {
            throw NativeError.unavailable("The downloaded model file \(file.name) has the wrong size.")
        }
        guard verifyChecksum, !file.checksum.isEmpty else { return }
        let actual: String
        switch file.checksumType.lowercased() {
        case "crc32c": actual = try CRC32C.base64Digest(at: url)
        case "sha256": actual = try SHA256Digest.hex(at: url)
        default: throw NativeError.unavailable("The model catalog uses an unsupported checksum for \(file.name).")
        }
        guard actual == file.checksum else {
            throw NativeError.unavailable("The downloaded model file \(file.name) failed its integrity check.")
        }
    }

    private static func verify(_ files: [ModelAsset], in directory: URL, verifyChecksums: Bool = true) throws {
        for file in files {
            guard isSafeRelativePath(file.name) else {
                throw NativeError.unavailable("The model catalog contains an unsafe file path.")
            }
            let destination = file.name.split(separator: "/").reduce(directory) {
                $0.appendingPathComponent(String($1), isDirectory: false)
            }
            try verify(file, at: destination, verifyChecksum: verifyChecksums)
        }
    }

    private static func isSafeRelativePath(_ path: String) -> Bool {
        !path.isEmpty && !path.hasPrefix("/") && path.split(separator: "/", omittingEmptySubsequences: false)
            .allSatisfy { !$0.isEmpty && $0 != "." && $0 != ".." }
    }

    private static func install(staging: URL, destination: URL, backup: URL, fileManager: FileManager) throws {
        installLock.lock()
        defer { installLock.unlock() }
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.moveItem(at: destination, to: backup)
        }
        do {
            try fileManager.moveItem(at: staging, to: destination)
            try? fileManager.removeItem(at: backup)
        } catch {
            if fileManager.fileExists(atPath: backup.path), !fileManager.fileExists(atPath: destination.path) {
                try? fileManager.moveItem(at: backup, to: destination)
            }
            throw error
        }
    }

    private static func previousDirectories(for modelDirectory: URL, fileManager: FileManager) -> [URL] {
        let parent = modelDirectory.deletingLastPathComponent()
        let prefix = ".\(modelDirectory.lastPathComponent).previous-"
        return ((try? fileManager.contentsOfDirectory(at: parent, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.lastPathComponent.hasPrefix(prefix) }
    }

    private static func removeStaleBackups(for modelDirectory: URL, fileManager: FileManager) {
        for backup in previousDirectories(for: modelDirectory, fileManager: fileManager) {
            try? fileManager.removeItem(at: backup)
        }
    }
}

private final class ModelFileDownload: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let onProgress: @Sendable (Double) -> Void
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Void, Error>?
    private var session: URLSession?
    private var task: URLSessionDataTask?
    private var output: FileHandle?
    private var received: Int64 = 0
    private var expected: Int64 = -1
    private var responseError: Error?
    private var wasCancelled = false

    init(onProgress: @escaping @Sendable (Double) -> Void) {
        self.onProgress = onProgress
    }

    func download(_ url: URL, to destination: URL) async throws {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                lock.lock()
                self.continuation = continuation
                do {
                    FileManager.default.createFile(atPath: destination.path, contents: nil)
                    output = try FileHandle(forWritingTo: destination)
                    let configuration = URLSessionConfiguration.ephemeral
                    configuration.waitsForConnectivity = true
                    let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
                    self.session = session
                    let task = session.dataTask(with: url)
                    self.task = task
                    let wasCancelled = self.wasCancelled
                    lock.unlock()
                    task.resume()
                    if wasCancelled { task.cancel() }
                } catch {
                    lock.unlock()
                    finish(error)
                }
            }
        } onCancel: {
            self.cancel()
        }
    }

    func cancel() {
        lock.lock()
        wasCancelled = true
        let task = self.task
        lock.unlock()
        task?.cancel()
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        if let response = response as? HTTPURLResponse, !(200...299).contains(response.statusCode) {
            responseError = NativeError.unavailable("Speech model download failed with HTTP \(response.statusCode).")
            completionHandler(.cancel)
            return
        }
        expected = response.expectedContentLength
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        do {
            try output?.write(contentsOf: data)
            received += Int64(data.count)
            if expected > 0 { onProgress(min(0.99, Double(received) / Double(expected))) }
        } catch {
            responseError = error
            dataTask.cancel()
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        let finalError = error ?? responseError
        do { try output?.close() } catch {}
        output = nil
        if finalError == nil, received == 0 {
            finish(NativeError.unavailable("The speech model server returned an empty file."))
        } else {
            finish(finalError)
        }
        session.finishTasksAndInvalidate()
    }

    private func finish(_ error: Error?) {
        lock.lock()
        let continuation = self.continuation
        self.continuation = nil
        lock.unlock()
        guard let continuation else { return }
        if let error { continuation.resume(throwing: error) }
        else { continuation.resume() }
    }
}

private enum CRC32C {
    static func base64Digest(at url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var crc: UInt32 = 0xffff_ffff
        while let data = try handle.read(upToCount: 64 * 1024), !data.isEmpty {
            for byte in data {
                crc ^= UInt32(byte)
                for _ in 0..<8 {
                    crc = (crc & 1) == 1 ? (crc >> 1) ^ 0x82f6_3b78 : crc >> 1
                }
            }
        }
        crc ^= 0xffff_ffff
        var bigEndian = crc.bigEndian
        let bytes = withUnsafeBytes(of: &bigEndian) { Data($0) }
        return bytes.base64EncodedString()
    }
}

private enum SHA256Digest {
    static func hex(at url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let data = try handle.read(upToCount: 1024 * 1024), !data.isEmpty {
            hasher.update(data: data)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
