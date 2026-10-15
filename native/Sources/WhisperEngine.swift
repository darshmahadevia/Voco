import Foundation
import Whisper

private final class WhisperCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false

    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }

    func cancel() {
        lock.lock()
        cancelled = true
        lock.unlock()
    }
}

private struct WhisperStream {
    var samples: [Float] = []
    let cancellation = WhisperCancellation()
    var isFinishing = false

}

final class WhisperEngine: SpeechEngine, @unchecked Sendable {
    private let queue = DispatchQueue(label: "org.vocoapp.Voco.whisper", qos: .userInitiated)
    private let audioLock = NSLock()
    private var context: OpaquePointer?
    private var modelPath: String?
    private var streams: [SpeechStreamID: WhisperStream] = [:]

    func warm(modelDirectory: URL, completion: @escaping @MainActor @Sendable (Result<Void, Error>) -> Void) {
        queue.async {
            let result = Result { try self.loadLocked(modelDirectory: modelDirectory) }
            DispatchQueue.main.async { completion(result) }
        }
    }

    func unload() {
        audioLock.lock()
        for state in streams.values { state.cancellation.cancel() }
        audioLock.unlock()
        queue.sync {
            audioLock.lock()
            streams.removeAll()
            audioLock.unlock()
            if let context { whisper_free(context) }
            context = nil
            modelPath = nil
        }
    }

    private func loadLocked(modelDirectory: URL) throws {
        if context != nil, modelPath == modelDirectory.path { return }
        if let context { whisper_free(context) }
        context = nil
        modelPath = nil
        let modelURL = modelDirectory.appendingPathComponent("ggml-large-v3-turbo.bin")
        var parameters = whisper_context_default_params()
        parameters.use_gpu = true
        parameters.flash_attn = true
        guard let loaded = modelURL.path.withCString({ whisper_init_from_file_with_params($0, parameters) }) else {
            throw NativeError.unavailable("Whisper could not load its model file.")
        }
        context = loaded
        modelPath = modelDirectory.path
    }

    func openStream() throws -> SpeechStreamID {
        try queue.sync {
            guard context != nil else { throw NativeError.unavailable("The Whisper model is not ready.") }
            let stream = SpeechStreamID()
            audioLock.lock()
            streams[stream] = WhisperStream()
            audioLock.unlock()
            return stream
        }
    }

    func addAudio(_ samples: UnsafeBufferPointer<Float>, to stream: SpeechStreamID) throws {
        guard !samples.isEmpty else { return }
        audioLock.lock()
        defer { audioLock.unlock() }
        guard var state = streams[stream], !state.isFinishing else { throw NativeError.unavailable("The Whisper session has already ended.") }
        state.samples.append(contentsOf: samples)
        streams[stream] = state
    }

    func enqueueAudio(
        _ samples: UnsafeBufferPointer<Float>,
        to stream: SpeechStreamID,
        onFailure: @escaping @Sendable (String) -> Void
    ) {
        guard !samples.isEmpty else { return }
        let copy = Array(samples)
        audioLock.lock()
        guard var state = streams[stream], !state.isFinishing else {
            audioLock.unlock()
            onFailure("The Whisper session has already ended.")
            return
        }
        state.samples.append(contentsOf: copy)
        streams[stream] = state
        audioLock.unlock()
    }

    func finish(
        stream: SpeechStreamID,
        completion: @escaping @MainActor @Sendable (Result<[SpeechLine], Error>) -> Void
    ) {
        queue.async {
            guard let context = self.context else {
                DispatchQueue.main.async { completion(.failure(NativeError.unavailable("The Whisper model is not ready."))) }
                return
            }
            self.audioLock.lock()
            guard var state = self.streams[stream], !state.isFinishing else {
                self.audioLock.unlock()
                DispatchQueue.main.async { completion(.failure(NativeError.unavailable("The Whisper session has already ended."))) }
                return
            }
            // Keep cancellation reachable until the main queue delivers the final result.
            state.isFinishing = true
            self.streams[stream] = state
            self.audioLock.unlock()
            let cancellation = state.cancellation
            let result = Result {
                try self.transcribeLocked(context: context, samples: state.samples, cancellation: cancellation)
            }
            DispatchQueue.main.async {
                self.audioLock.lock()
                self.streams.removeValue(forKey: stream)
                self.audioLock.unlock()
                completion(cancellation.isCancelled ? .success([]) : result.map { text in
                    text.isEmpty ? [] : [SpeechLine(text: text, complete: true)]
                })
            }
        }
    }

    func cancel(stream: SpeechStreamID) {
        audioLock.lock()
        streams.removeValue(forKey: stream)?.cancellation.cancel()
        audioLock.unlock()
    }

    private func transcribeLocked(
        context: OpaquePointer,
        samples: [Float],
        cancellation: WhisperCancellation
    ) throws -> String {
        guard !cancellation.isCancelled else { return "" }
        guard samples.contains(where: { $0 != 0 }) else { return "" }
        var parameters = whisper_full_default_params(WHISPER_SAMPLING_GREEDY)
        parameters.n_threads = Int32(max(1, min(8, ProcessInfo.processInfo.activeProcessorCount)))
        parameters.no_context = true
        parameters.print_progress = false
        parameters.print_realtime = false
        parameters.print_timestamps = false
        parameters.suppress_nst = true
        parameters.no_speech_thold = 0.6
        parameters.temperature = 0
        // whisper_full borrows this pointer until it returns, including backend worker callbacks.
        let retainedCancellation = Unmanaged.passRetained(cancellation)
        defer { retainedCancellation.release() }
        parameters.abort_callback_user_data = retainedCancellation.toOpaque()
        parameters.abort_callback = { userData in
            guard let userData else { return false }
            return Unmanaged<WhisperCancellation>.fromOpaque(userData).takeUnretainedValue().isCancelled
        }
        let status = "en".withCString { language in
            parameters.language = language
            return samples.withUnsafeBufferPointer { audio in
                guard let baseAddress = audio.baseAddress else { return Int32(-1) }
                return whisper_full(context, parameters, baseAddress, Int32(audio.count))
            }
        }
        guard !cancellation.isCancelled else { return "" }
        guard status == 0 else { throw NativeError.unavailable("Whisper could not transcribe the current phrase.") }
        let count = Int(whisper_full_n_segments(context))
        let segments = (0..<count).compactMap { index -> String? in
            guard let value = whisper_full_get_segment_text(context, Int32(index)) else { return nil }
            return String(cString: value).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return TranscriptText.join(segments)
    }
}
