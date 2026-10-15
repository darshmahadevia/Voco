import AVFoundation
import Foundation

// The focused executable compiles the real engine without the app coordinator.
enum NativeError: LocalizedError {
    case unavailable(String)
    var errorDescription: String? {
        switch self { case let .unavailable(message): message }
    }
}

@main
@MainActor
enum WhisperCancellationCheck {
    static func main() async throws {
        let model = URL(fileURLWithPath: CommandLine.arguments[1])
        let audio = try AVAudioFile(
            forReading: URL(fileURLWithPath: CommandLine.arguments[2]),
            commonFormat: .pcmFormatFloat32, interleaved: false
        )
        precondition(audio.processingFormat.sampleRate == 16_000)
        let buffer = AVAudioPCMBuffer(pcmFormat: audio.processingFormat, frameCapacity: AVAudioFrameCount(audio.length))!
        try audio.read(into: buffer)
        let phrase = Array(UnsafeBufferPointer(start: buffer.floatChannelData![0], count: Int(buffer.frameLength)))
        precondition(!phrase.isEmpty)
        let longAudio = Array(repeating: phrase, count: max(1, 120 * 16_000 / phrase.count)).flatMap { $0 }
        let engine = WhisperEngine()
        try engine.loadIfNeeded(modelDirectory: model)
        defer { engine.unload() }

        // Establish that this exact long input really decodes successfully before testing abort.
        let baseline = try engine.openStream()
        try longAudio.withUnsafeBufferPointer { try engine.addAudio($0, to: baseline) }
        let baselineStart = Date()
        let baselineLines = try await finish(engine, baseline)
        let baselineDuration = Date().timeIntervalSince(baselineStart)
        precondition(!baselineLines.isEmpty, "Control inference must produce text")
        print("Control inference completed in \(baselineDuration)s")

        for operation in ["finish", "transcribe", "synchronous finish"] {
            let stream = try engine.openStream()
            try longAudio.withUnsafeBufferPointer { try engine.addAudio($0, to: stream) }
            let completion = Task { @MainActor in
                try await withCheckedThrowingContinuation { continuation in
                    if operation == "finish" {
                        engine.finish(stream: stream) { continuation.resume(with: $0) }
                    } else if operation == "transcribe" {
                        engine.transcribe(stream: stream) { continuation.resume(with: $0) }
                    } else {
                        DispatchQueue.global().async {
                            continuation.resume(with: Result { try engine.finishSynchronously(stream: stream) })
                        }
                    }
                }
            }
            // Give actual inference time to enter whisper_full, then cancel from the caller.
            try await Task.sleep(for: .milliseconds(500))
            let cancelStart = Date()
            engine.cancel(stream: stream)
            let next = try engine.openStream()
            let reopenDuration = Date().timeIntervalSince(cancelStart)
            engine.cancel(stream: next)
            let cancelledLines = try await completion.value
            precondition(cancelledLines.isEmpty, "Cancelled \(operation) published text")
            precondition(reopenDuration < 3, "Next open waited \(reopenDuration)s after cancelling \(operation)")
            precondition(reopenDuration < baselineDuration / 2, "Cancellation did not interrupt the control workload")
            print("PASS \(operation): cancelled and reopened in \(reopenDuration)s, no stale text")
        }

        // Keep the main queue occupied until inference and its result dispatch have completed.
        // Cancellation must still suppress a result already waiting for main-queue delivery.
        let pending = try engine.openStream()
        try phrase.withUnsafeBufferPointer { try engine.addAudio($0, to: pending) }
        let queuedResult: [SpeechLine] = try await withCheckedThrowingContinuation { continuation in
            engine.finish(stream: pending) { continuation.resume(with: $0) }
            do {
                let barrier = try engine.openStream()
                engine.cancel(stream: pending)
                engine.cancel(stream: barrier)
            } catch { fatalError("Queue barrier failed: \(error)") }
        }
        precondition(queuedResult.isEmpty, "Cancellation published a queued final result")
        print("PASS cancellation suppresses final text already queued for delivery")

        for cached in [false, true] {
            let partial = try engine.openStream()
            try phrase.withUnsafeBufferPointer { try engine.addAudio($0, to: partial) }
            if cached {
                let initial: [SpeechLine] = try await withCheckedThrowingContinuation { continuation in
                    engine.transcribe(stream: partial) { continuation.resume(with: $0) }
                }
                precondition(!initial.isEmpty, "Cached partial needs a real transcript")
            }
            let delivered: [SpeechLine] = try await withCheckedThrowingContinuation { continuation in
                engine.transcribe(stream: partial) { continuation.resume(with: $0) }
                do {
                    let barrier = try engine.openStream()
                    engine.cancel(stream: partial)
                    engine.cancel(stream: barrier)
                } catch { fatalError("Queue barrier failed: \(error)") }
            }
            precondition(delivered.isEmpty, "Cancellation published queued partial text")
            print("PASS cancellation suppresses queued \(cached ? "cached" : "decoded") partial text")
        }

        let recovery = try engine.openStream()
        try phrase.withUnsafeBufferPointer { try engine.addAudio($0, to: recovery) }
        let recovered = try await finish(engine, recovery)
        precondition(!recovered.isEmpty && recovered.allSatisfy(\.complete), "Context did not recover after abort")
        print("PASS same context transcribes the next phrase: \(TranscriptLedger.join(recovered.map(\.text)))")
    }

    static func finish(_ engine: WhisperEngine, _ stream: SpeechStreamID) async throws -> [SpeechLine] {
        try await withCheckedThrowingContinuation { continuation in
            engine.finish(stream: stream) { continuation.resume(with: $0) }
        }
    }
}
