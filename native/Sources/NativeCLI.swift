import Foundation

enum NativeCLI {
    static func handles(_ arguments: [String]) -> Bool {
        arguments.contains("--download-model") || arguments.contains("--transcribe-file")
            || arguments.contains("--model-status") || arguments.contains("--smoke-status")
            || arguments.contains("--model-manifest") || arguments.contains("--verify-live-insertion") || arguments.contains("--stream-transcribe-file")
            || arguments.contains("--verify-empty-rich-editor")
            || arguments.contains("--verify-microphone")
    }

    @MainActor
    static func run(_ arguments: [String]) async -> Int32 {
        do {
            if arguments.contains("--verify-microphone") {
                try await verifyMicrophone(arguments)
                return 0
            }
            if arguments.contains("--verify-empty-rich-editor") {
                try await verifyEmptyRichEditor()
                return 0
            }
            if let expected = value(after: "--verify-live-insertion", in: arguments) {
                var engine: MoonshineEngine?
                let fixture = value(after: "--audio-fixture", in: arguments).map { URL(fileURLWithPath: $0) }
                if fixture != nil {
                    guard let model = value(after: "--model-directory", in: arguments) else { throw NativeError.invalidCommand("Pass --model-directory PATH with --audio-fixture.") }
                    let speechEngine = MoonshineEngine()
                    try speechEngine.loadIfNeeded(modelDirectory: URL(fileURLWithPath: model))
                    engine = speechEngine
                }
                try await verifyLiveInsertion(expected: expected, audioFixture: fixture, engine: engine)
                return 0
            }
            guard let modelPath = value(after: "--model-directory", in: arguments) else {
                throw NativeError.invalidCommand("Pass --model-directory PATH.")
            }
            let modelDirectory = URL(fileURLWithPath: modelPath)
            let installer = ModelInstaller(modelDirectory: modelDirectory)
            let engine = MoonshineEngine()

            if arguments.contains("--model-manifest") {
                let files = try MoonshineCatalog.englishMediumStreamingFiles()
                let manifest = files.map { file in
                    [
                        "name": file.name,
                        "url": file.url.absoluteString,
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
                try engine.loadIfNeeded(modelDirectory: modelDirectory)
                print("READY — English Medium Streaming loaded")
                return 0
            }

            if arguments.contains("--download-model") {
                try await installer.download { file, progress in
                    FileHandle.standardError.write(Data("\(Int(progress * 100))% · \(file)\n".utf8))
                }
                try engine.loadIfNeeded(modelDirectory: modelDirectory)
                print("READY — English Medium Streaming downloaded and loaded")
                return 0
            }

            let streamingPath = value(after: "--stream-transcribe-file", in: arguments)
            guard let fixturePath = streamingPath ?? value(after: "--transcribe-file", in: arguments) else {
                throw NativeError.invalidCommand("Pass --transcribe-file PATH.")
            }
            guard try installer.verifyCachedModel() else {
                throw NativeError.unavailable("The speech model is missing. Run --download-model first.")
            }
            try engine.loadIfNeeded(modelDirectory: modelDirectory)
            if streamingPath != nil {
                var partialUpdates = 0
                var previous = ""
                let final = try await transcribeStreamingFile(URL(fileURLWithPath: fixturePath), engine: engine) { lines in
                    let text = TranscriptLedger.join(lines.map(\.text))
                    if !text.isEmpty, text != previous {
                        print("Partial: \(text)")
                        previous = text
                        if lines.contains(where: { !$0.complete }) { partialUpdates += 1 }
                    }
                }
                guard partialUpdates > 0 else { throw NativeError.unavailable("No partial transcripts were observed.") }
                print("Final: \(TranscriptLedger.join(final.map(\.text)))")
                print("Streaming speech checks: PASS (\(partialUpdates) partial updates)")
                return 0
            }
            let stream = try engine.openStream()
            do {
                try await NativeAudioFile.feed(URL(fileURLWithPath: fixturePath), to: engine, stream: stream)
            } catch {
                engine.cancel(stream: stream)
                throw error
            }
            let lines = try engine.finishSynchronously(stream: stream)
            let text = lines.map(\.text).joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
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
    private static func verifyMicrophone(_ arguments: [String]) async throws {
        guard let durationValue = value(after: "--verify-microphone", in: arguments),
              let seconds = Double(durationValue), seconds.isFinite, (1...30).contains(seconds),
              let modelPath = value(after: "--model-directory", in: arguments) else {
            throw NativeError.invalidCommand("Pass --verify-microphone SECONDS (1–30) and --model-directory PATH.")
        }
        guard PermissionSnapshot.microphoneStatus() == "granted" else { throw NativeError.microphone }
        let directory = URL(fileURLWithPath: modelPath)
        guard try ModelInstaller(modelDirectory: directory).verifyCachedModel() else {
            throw NativeError.unavailable("The speech model is missing. Run --download-model first.")
        }
        let engine = MoonshineEngine()
        try engine.loadIfNeeded(modelDirectory: directory)
        let stream = try engine.openStream()
        let audio = NativeAudioInput()
        defer { audio.stop(); engine.cancel(stream: stream) }
        var callbacks = 0
        var speechCallbacks = 0
        var maximumLevel: Double = 0
        var partialUpdates = 0
        var ledger = TranscriptLedger()
        var microphoneFailure: String?
        try audio.start(moonshine: engine, stream: stream,
                        onSpeech: { speechCallbacks += 1 },
                        onLevel: { level in callbacks += 1; maximumLevel = max(maximumLevel, level) },
                        onFailure: { microphoneFailure = $0 })
        let deadline = ContinuousClock.now + .seconds(seconds)
        while ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(240))
            if let microphoneFailure { throw NativeError.unavailable(microphoneFailure) }
            let lines = try await withCheckedThrowingContinuation { continuation in
                engine.transcribe(stream: stream) { continuation.resume(with: $0) }
            }
            ledger.update(lines)
            if lines.contains(where: { !$0.complete && !$0.text.isEmpty }) { partialUpdates += 1 }
        }
        audio.stop()
        if let microphoneFailure { throw NativeError.unavailable(microphoneFailure) }
        let finalLines = try await withCheckedThrowingContinuation { continuation in
            engine.finish(stream: stream) { continuation.resume(with: $0) }
        }
        ledger.update(finalLines)
        guard callbacks > 0 else { throw NativeError.unavailable("The microphone delivered no audio callbacks.") }
        try writeVerificationReport([
            "status": "pass", "microphone": PermissionSnapshot.microphoneStatus(),
            "seconds": seconds, "audioCallbacks": callbacks, "speechCallbacks": speechCallbacks,
            "maximumLevel": maximumLevel, "partialUpdates": partialUpdates, "transcript": ledger.text,
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

    static func value(after flag: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else { return nil }
        return arguments[index + 1]
    }
}
