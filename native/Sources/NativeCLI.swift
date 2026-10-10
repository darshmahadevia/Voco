import AVFoundation
import Darwin
import Foundation
import VocoCore

enum NativeCLI {
    static func handles(_ arguments: [String]) -> Bool {
        arguments.contains("--download-model") || arguments.contains("--transcribe-file")
            || arguments.contains("--model-status") || arguments.contains("--smoke-status")
            || arguments.contains("--model-manifest") || arguments.contains("--verify-live-insertion") || arguments.contains("--stream-transcribe-file")
            || arguments.contains("--verify-empty-rich-editor")
            || arguments.contains("--verify-buffered-insertion")
            || arguments.contains("--verify-microphone") || arguments.contains("--benchmark-file")
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
            if arguments.contains("--verify-empty-rich-editor") {
                try await verifyEmptyRichEditor()
                return 0
            }
            if let expected = value(after: "--verify-live-insertion", in: arguments) {
                var engine: (any SpeechEngine)?
                defer { engine?.unload() }
                let fixture = value(after: "--audio-fixture", in: arguments).map { URL(fileURLWithPath: $0) }
                if fixture != nil {
                    guard let model = value(after: "--model-directory", in: arguments) else { throw NativeError.invalidCommand("Pass --model-directory PATH with --audio-fixture.") }
                    let speechEngine = try chosenEngine(arguments)
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
            let modelID = try chosenModel(arguments)
            let variant = try chosenVariant(arguments)
            let installer = ModelInstaller(modelDirectory: modelDirectory, modelID: modelID, whisperVariant: variant)
            let engine = SpeechModelCatalog.makeEngine(for: modelID, whisperVariant: variant)
            defer { engine.unload() }

            if arguments.contains("--model-manifest") {
                let files = try SpeechModelCatalog.assets(for: modelID, whisperVariant: variant)
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
                try engine.loadIfNeeded(modelDirectory: modelDirectory)
                print("READY · \(engine.descriptor.name) loaded")
                return 0
            }

            if arguments.contains("--download-model") {
                try await installer.download { file, progress in
                    FileHandle.standardError.write(Data("\(Int(progress * 100))% · \(file)\n".utf8))
                }
                try engine.loadIfNeeded(modelDirectory: modelDirectory)
                print("READY · \(engine.descriptor.name) downloaded and loaded")
                return 0
            }

            if let benchmarkPath = value(after: "--benchmark-file", in: arguments) {
                guard try installer.verifyCachedModel(verifyChecksums: false) else {
                    throw NativeError.unavailable("The speech model is missing. Run --download-model first.")
                }
                try await benchmark(URL(fileURLWithPath: benchmarkPath), engine: engine,
                                    modelDirectory: modelDirectory, arguments: arguments)
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
            let lines = try await transcribeFile(URL(fileURLWithPath: fixturePath), engine: engine)
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
    private static func verifyBufferedInsertion(transcript: String, arguments: [String]) async throws {
        guard let captured = FocusTarget.capture() else { throw InsertionError.focusUnavailable }
        let target = try await captured.resolved()
        var text = transcript
        if let fixture = value(after: "--audio-fixture", in: arguments) {
            guard let modelPath = value(after: "--model-directory", in: arguments) else {
                throw NativeError.invalidCommand("Pass --model-directory PATH with --audio-fixture.")
            }
            let directory = URL(fileURLWithPath: modelPath)
            let installer = ModelInstaller(modelDirectory: directory, modelID: try chosenModel(arguments), whisperVariant: try chosenVariant(arguments))
            guard try installer.verifyCachedModel() else { throw NativeError.unavailable("The speech model is missing. Run --download-model first.") }
            let engine = try chosenEngine(arguments)
            defer { engine.unload() }
            try engine.loadIfNeeded(modelDirectory: directory)
            let lines = try await transcribeFile(URL(fileURLWithPath: fixture), engine: engine)
            guard lines.allSatisfy(\.complete) else { throw NativeError.unavailable("The speech model returned an unfinished phrase.") }
            text = TranscriptLedger.join(lines.map(\.text))
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
            return try engine.finishSynchronously(stream: stream)
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
        guard try ModelInstaller(modelDirectory: directory, modelID: try chosenModel(arguments), whisperVariant: try chosenVariant(arguments)).verifyCachedModel() else {
            throw NativeError.unavailable("The speech model is missing. Run --download-model first.")
        }
        let engine = try chosenEngine(arguments)
        defer { engine.unload() }
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
        try audio.start(engine: engine, stream: stream,
                        onSpeech: { speechCallbacks += 1 },
                        onLevel: { level, _ in callbacks += 1; maximumLevel = max(maximumLevel, level) },
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

    private static func chosenModel(_ arguments: [String]) throws -> SpeechModelID {
        guard let id = SpeechModelID(rawValue: value(after: "--model", in: arguments) ?? "moonshine") else {
            throw NativeError.invalidCommand("Unknown speech model. Choose moonshine, parakeet, or whisper.")
        }
        return id
    }

    private static func chosenVariant(_ arguments: [String]) throws -> WhisperModelVariant {
        guard let value = value(after: "--whisper-variant", in: arguments) else { return .largeV3Turbo }
        switch value {
        case "large-v3": return .largeV3
        case "large-v3-turbo": return .largeV3Turbo
        default: throw NativeError.invalidCommand("Unknown Whisper benchmark variant.")
        }
    }

    private static func chosenEngine(_ arguments: [String]) throws -> any SpeechEngine {
        SpeechModelCatalog.makeEngine(for: try chosenModel(arguments), whisperVariant: try chosenVariant(arguments))
    }

    @MainActor
    private static func benchmark(_ url: URL, engine: any SpeechEngine,
                                  modelDirectory: URL, arguments: [String]) async throws {
        let warmups = Int(value(after: "--warmups", in: arguments) ?? "0")
        let repetitions = Int(value(after: "--repetitions", in: arguments) ?? "2")
        guard let warmups, let repetitions, (0...10).contains(warmups), (1...20).contains(repetitions) else {
            throw NativeError.invalidCommand("Benchmark warmups must be 0–10 and repetitions 1–20.")
        }
        let file = try AVAudioFile(forReading: url)
        guard file.processingFormat.sampleRate == 16_000, file.processingFormat.channelCount == 1,
              file.length > 0, file.length < Int64(UInt32.max),
              let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)) else {
            throw NativeError.invalidCommand("Benchmark fixtures must be nonempty mono 16 kHz audio.")
        }
        try file.read(into: buffer)
        guard let channel = buffer.floatChannelData?[0] else {
            throw NativeError.invalidCommand("The benchmark fixture could not be decoded to Float32.")
        }
        let samples = Array(UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength)))
        let loadStart = ProcessInfo.processInfo.systemUptime
        try engine.loadIfNeeded(modelDirectory: modelDirectory)
        let loadMs = (ProcessInfo.processInfo.systemUptime - loadStart) * 1_000
        defer { engine.unload() }
        for index in 0..<(warmups + repetitions) {
            let measurement = try await pacedRun(samples, engine: engine)
            guard index >= warmups else { continue }
            var usage = rusage()
            getrusage(RUSAGE_SELF, &usage)
            try writeVerificationReport([
                "model": engine.descriptor.id.rawValue,
                "audioDurationMs": Double(samples.count) / 16,
                "loadMs": index == warmups ? loadMs : 0,
                "firstPartialMs": measurement.firstPartialMs.map { $0 as Any } ?? NSNull(),
                "firstStableMs": measurement.firstStableMs.map { $0 as Any } ?? NSNull(),
                "releaseToFinalMs": measurement.releaseToFinalMs,
                "transcript": measurement.ledger.text,
                "deliveredTranscript": measurement.stableText.text,
                "peakMemoryBytes": usage.ru_maxrss,
                "coldStart": index == 0,
                "engineVersion": engine.descriptor.engineVersion,
                "modelVersion": engine.descriptor.modelVersion,
            ], arguments: [])
        }
    }

    @MainActor
    private static func pacedRun(_ samples: [Float], engine: any SpeechEngine) async throws -> BenchmarkMeasurement {
        let stream = try engine.openStream()
        let measurement = BenchmarkMeasurement()
        let start = ProcessInfo.processInfo.systemUptime
        var nextPoll = start
        do {
            for offset in stride(from: 0, to: samples.count, by: 800) {
                let deadline = start + Double(offset) / 16_000
                let wait = deadline - ProcessInfo.processInfo.systemUptime
                if wait > 0 { try await Task.sleep(for: .seconds(wait)) }
                if let error = measurement.failure { throw NativeError.unavailable(error) }
                samples.withUnsafeBufferPointer { all in
                    let chunk = UnsafeBufferPointer(rebasing: all[offset..<min(offset + 800, samples.count)])
                    engine.enqueueAudio(chunk, to: stream) { message in
                        Task { @MainActor in measurement.failure = message }
                    }
                }
                let now = ProcessInfo.processInfo.systemUptime
                if now >= nextPoll, !measurement.polling {
                    measurement.polling = true
                    nextPoll = now + 0.12
                    engine.transcribe(stream: stream) { result in
                        measurement.polling = false
                        guard !measurement.finished else { return }
                        switch result {
                        case .success(let lines):
                            if !measurement.released { measurement.update(lines, start: start) }
                        case .failure(let error): measurement.failure = error.localizedDescription
                        }
                    }
                }
            }
            let audioEnd = start + Double(samples.count) / 16_000
            let wait = audioEnd - ProcessInfo.processInfo.systemUptime
            if wait > 0 { try await Task.sleep(for: .seconds(wait)) }
            let release = ProcessInfo.processInfo.systemUptime
            measurement.released = true
            while measurement.polling { try await Task.sleep(for: .milliseconds(1)) }
            if let error = measurement.failure { throw NativeError.unavailable(error) }
            let final: [SpeechLine] = try await withCheckedThrowingContinuation { continuation in
                engine.finish(stream: stream) { continuation.resume(with: $0) }
            }
            measurement.releaseToFinalMs = (ProcessInfo.processInfo.systemUptime - release) * 1_000
            measurement.finished = true
            measurement.ledger.update(final)
            let complete = !measurement.ledger.pendingLines.isEmpty && measurement.ledger.pendingLines.allSatisfy(\.complete)
            let finalTime = ProcessInfo.processInfo.systemUptime
            measurement.stableText.update(measurement.ledger.text, final: complete, now: finalTime)
            if measurement.firstStableMs == nil, !measurement.stableText.text.isEmpty {
                measurement.firstStableMs = (finalTime - start) * 1_000
            }
            return measurement
        } catch {
            measurement.finished = true
            engine.cancel(stream: stream)
            throw error
        }
    }

    static func value(after flag: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else { return nil }
        return arguments[index + 1]
    }
}

@MainActor
private final class BenchmarkMeasurement {
    var ledger = TranscriptLedger()
    var stableText = StableText()
    var firstPartialMs: Double?
    var firstStableMs: Double?
    var releaseToFinalMs: Double = 0
    var failure: String?
    var polling = false
    var finished = false
    var released = false

    func update(_ lines: [SpeechLine], start: TimeInterval) {
        ledger.update(lines)
        let now = ProcessInfo.processInfo.systemUptime
        let elapsed = (now - start) * 1_000
        if firstPartialMs == nil, !ledger.text.isEmpty { firstPartialMs = elapsed }
        let confirmed = TranscriptLedger.join(ledger.committablePrefix.map(\.text))
            .split(whereSeparator: \.isWhitespace).count
        stableText.update(ledger.text, confirmedWordCount: confirmed, now: now)
        if firstStableMs == nil, !stableText.text.isEmpty { firstStableMs = elapsed }
    }
}
