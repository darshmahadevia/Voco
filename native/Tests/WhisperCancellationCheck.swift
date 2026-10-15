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
        try await engine.warm(modelDirectory: model)
        defer { engine.unload() }

        // Establish that this exact long input really decodes successfully before testing abort.
        let baseline = try engine.openStream()
        try longAudio.withUnsafeBufferPointer { try engine.addAudio($0, to: baseline) }
        let baselineStart = Date()
        let baselineLines = try await finish(engine, baseline)
        let baselineDuration = Date().timeIntervalSince(baselineStart)
        precondition(!baselineLines.isEmpty, "Control inference must produce text")
        print("Control inference completed in \(baselineDuration)s")

        do {
            let stream = try engine.openStream()
            try longAudio.withUnsafeBufferPointer { try engine.addAudio($0, to: stream) }
            let completion = Task { @MainActor in try await engine.finish(stream: stream) }
            // Give actual inference time to enter whisper_full, then cancel from the caller.
            try await Task.sleep(for: .milliseconds(500))
            let cancelStart = Date()
            engine.cancel(stream: stream)
            let next = try engine.openStream()
            let reopenDuration = Date().timeIntervalSince(cancelStart)
            engine.cancel(stream: next)
            let cancelledLines = try await completion.value
            precondition(cancelledLines.isEmpty, "Cancelled final inference published text")
            precondition(reopenDuration < 3, "Next open waited \(reopenDuration)s after cancelling final inference")
            precondition(reopenDuration < baselineDuration / 2, "Cancellation did not interrupt the control workload")
            print("PASS final inference: cancelled and reopened in \(reopenDuration)s, no stale text")
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

        let recovery = try engine.openStream()
        try phrase.withUnsafeBufferPointer { try engine.addAudio($0, to: recovery) }
        let recovered = try await finish(engine, recovery)
        precondition(!recovered.isEmpty && recovered.allSatisfy(\.complete), "Context did not recover after abort")
        print("PASS same context transcribes the next phrase: \(TranscriptText.join(recovered.map(\.text)))")
    }

    static func finish(_ engine: WhisperEngine, _ stream: SpeechStreamID) async throws -> [SpeechLine] {
        try await withCheckedThrowingContinuation { continuation in
            engine.finish(stream: stream) { continuation.resume(with: $0) }
        }
    }
}
