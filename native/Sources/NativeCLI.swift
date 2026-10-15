import AVFoundation
import Foundation
import VocoCore

enum NativeCLI {
    static func handles(_ arguments: [String]) -> Bool {
        arguments.contains("--download-model") || arguments.contains("--transcribe-file")
            || arguments.contains("--model-status") || arguments.contains("--smoke-status")
            || arguments.contains("--model-manifest")
            || arguments.contains("--verify-buffered-insertion")
            || arguments.contains("--verify-microphone")
    }

    @MainActor
    static func run(_ arguments: [String]) async -> Int32 {
        do {
            if let transcript = value(after: "--verify-buffered-insertion", in: arguments) {
                try await verifyBufferedInsertion(transcript: transcript, arguments: arguments)
                return 0
            }
            if arguments.contains("--verify-microphone") {
                try await verifyMicrophone(arguments)
                return 0
            }
            guard let modelPath = value(after: "--model-directory", in: arguments) else {
                throw NativeError.invalidCommand("Pass --model-directory PATH.")
            }
            let modelDirectory = URL(fileURLWithPath: modelPath)
            let modelID = try chosenModel(arguments)
            let installer = ModelInstaller(modelDirectory: modelDirectory, modelID: modelID)
            let engine = SpeechModelCatalog.makeEngine(for: modelID)
            defer { engine.unload() }

            if arguments.contains("--model-manifest") {
                let files = try SpeechModelCatalog.assets(for: modelID)
                let manifest = files.map { file in
                    [
                        "name": file.name,
                        "url": file.urlString,
                        "size": file.size.map(NSNumber.init(value:)) ?? NSNull(),
                        "checksum": file.checksum,
                        "checksum_type": file.checksumType,
                    ] as [String: Any]
                }
                let data = try JSONSerialization.data(withJSONObject: manifest, options: [.sortedKeys])
                print(String(decoding: data, as: UTF8.self))
                return 0
            }

            if arguments.contains("--model-status") || arguments.contains("--smoke-status") {
                guard try installer.verifyCachedModel() else {
                    print("MISSING")
                    return 0
                }
                try await engine.warm(modelDirectory: modelDirectory)
                print("READY · \(modelID.rawValue) loaded")
                return 0
            }

            if arguments.contains("--download-model") {
                try await installer.download { file, progress in
                    FileHandle.standardError.write(Data("\(Int(progress * 100))% · \(file)\n".utf8))
                }
                try await engine.warm(modelDirectory: modelDirectory)
                print("READY · \(modelID.rawValue) downloaded and loaded")
                return 0
            }

            guard let fixturePath = value(after: "--transcribe-file", in: arguments) else {
                throw NativeError.invalidCommand("Pass --transcribe-file PATH.")
            }
            guard try installer.verifyCachedModel() else {
                throw NativeError.unavailable("The speech model is missing. Run --download-model first.")
            }
            try await engine.warm(modelDirectory: modelDirectory)
            let lines = try await transcribeFile(URL(fileURLWithPath: fixturePath), engine: engine)
            let text = TranscriptText.join(lines.map(\.text))
            guard !text.isEmpty else { throw NativeError.noTranscript }
            print(text)
            return 0
        } catch {
            if arguments.contains("--verify-microphone") {
                try? writeVerificationReport([
                    "status": "error", "error": error.localizedDescription,
                    "microphone": PermissionSnapshot.microphoneStatus(),
                ], arguments: arguments)
            }
            FileHandle.standardError.write(Data("Voco native: \(error.localizedDescription)\n".utf8))
            return 1
        }
    }

    @MainActor
    private static func verifyBufferedInsertion(transcript: String, arguments: [String]) async throws {
        guard let captured = FocusTarget.capture() else { throw InsertionError.focusUnavailable }
        let target = try await captured.resolved()
        var text = transcript
        if let fixture = value(after: "--audio-fixture", in: arguments) {
            guard let modelPath = value(after: "--model-directory", in: arguments) else {
                throw NativeError.invalidCommand("Pass --model-directory PATH with --audio-fixture.")
            }
            let directory = URL(fileURLWithPath: modelPath)
            let installer = ModelInstaller(modelDirectory: directory, modelID: try chosenModel(arguments))
            guard try installer.verifyCachedModel() else { throw NativeError.unavailable("The speech model is missing. Run --download-model first.") }
            let engine = try chosenEngine(arguments)
            defer { engine.unload() }
            try await engine.warm(modelDirectory: directory)
            let lines = try await transcribeFile(URL(fileURLWithPath: fixture), engine: engine)
            guard lines.allSatisfy(\.complete) else { throw NativeError.unavailable("The speech model returned an unfinished phrase.") }
            text = TranscriptText.join(lines.map(\.text))
        }
        guard !text.isEmpty else { throw NativeError.noTranscript }
        try await target.insert(text)
        print("Final: \(text)")
        print("Buffered insertion checks: PASS")
    }

    @MainActor
    private static func transcribeFile(_ url: URL, engine: any SpeechEngine) async throws -> [SpeechLine] {
        let stream = try engine.openStream()
        do {
            try await NativeAudioFile.feed(url, to: engine, stream: stream)
            return try await engine.finish(stream: stream)
        } catch {
            engine.cancel(stream: stream)
            throw error
        }
    }

    @MainActor
    private static func verifyMicrophone(_ arguments: [String]) async throws {
        guard let durationValue = value(after: "--verify-microphone", in: arguments),
              let seconds = Double(durationValue), seconds.isFinite, (1...30).contains(seconds),
              let modelPath = value(after: "--model-directory", in: arguments) else {
            throw NativeError.invalidCommand("Pass --verify-microphone SECONDS (1–30) and --model-directory PATH.")
        }
        guard PermissionSnapshot.microphoneStatus() == "granted" else { throw NativeError.microphone }
        let directory = URL(fileURLWithPath: modelPath)
        guard try ModelInstaller(modelDirectory: directory, modelID: try chosenModel(arguments)).verifyCachedModel() else {
            throw NativeError.unavailable("The speech model is missing. Run --download-model first.")
        }
        let engine = try chosenEngine(arguments)
        defer { engine.unload() }
        try await engine.warm(modelDirectory: directory)
        let stream = try engine.openStream()
        let audio = NativeAudioInput()
        defer { audio.stop(); engine.cancel(stream: stream) }
        var callbacks = 0
        var speechCallbacks = 0
        var maximumLevel: Double = 0
        var microphoneFailure: String?
        try audio.start(engine: engine, stream: stream,
                        onSpeech: { speechCallbacks += 1 },
                        onLevel: { level, _ in callbacks += 1; maximumLevel = max(maximumLevel, level) },
                        onFailure: { microphoneFailure = $0 })
        let deadline = ContinuousClock.now + .seconds(seconds)
        while ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(240))
            if let microphoneFailure { throw NativeError.unavailable(microphoneFailure) }
        }
        audio.stop()
        if let microphoneFailure { throw NativeError.unavailable(microphoneFailure) }
        let finalLines = try await withCheckedThrowingContinuation { continuation in
            engine.finish(stream: stream) { continuation.resume(with: $0) }
        }
        guard callbacks > 0 else { throw NativeError.unavailable("The microphone delivered no audio callbacks.") }
        try writeVerificationReport([
            "status": "pass", "microphone": PermissionSnapshot.microphoneStatus(),
            "seconds": seconds, "audioCallbacks": callbacks, "speechCallbacks": speechCallbacks,
            "maximumLevel": maximumLevel, "transcript": TranscriptText.join(finalLines.map(\.text)),
        ], arguments: arguments)
    }

    private static func writeVerificationReport(_ report: [String: Any], arguments: [String]) throws {
        let data = try JSONSerialization.data(withJSONObject: report, options: [.sortedKeys])
        if let output = value(after: "--verification-output", in: arguments) {
            try data.write(to: URL(fileURLWithPath: output), options: .atomic)
        }
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data([0x0a]))
    }

    private static func chosenModel(_ arguments: [String]) throws -> SpeechModelID {
        guard let id = SpeechModelID(rawValue: value(after: "--model", in: arguments) ?? "moonshine") else {
            throw NativeError.invalidCommand("Unknown speech model. Choose moonshine, parakeet, or whisper.")
        }
        return id
    }

    private static func chosenEngine(_ arguments: [String]) throws -> any SpeechEngine {
        SpeechModelCatalog.makeEngine(for: try chosenModel(arguments))
    }

    static func value(after flag: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else { return nil }
        return arguments[index + 1]
    }
}
