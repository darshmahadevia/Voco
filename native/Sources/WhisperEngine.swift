import Foundation
import Whisper

private struct WhisperStream {
    var samples: [Float] = []
    var latestText = ""
    var lastDecodedSampleCount = 0
    var generation = UUID()

    func lines(complete: Bool = false) -> [SpeechLine] {
        guard !latestText.isEmpty else { return [] }
        return [SpeechLine(
            id: 1,
            start: 0,
            end: Double(samples.count) / 16_000,
            text: latestText,
            complete: complete
        )]
    }
}

final class WhisperEngine: SpeechEngine, @unchecked Sendable {
    let descriptor: SpeechModelDescriptor
    private let variant: WhisperModelVariant
    private let queue = DispatchQueue(label: "org.vocoapp.Voco.whisper", qos: .userInitiated)
    private let audioLock = NSLock()
    private let updateStrideSamples = 32_000
    private var context: OpaquePointer?
    private var modelPath: String?
    private var streams: [SpeechStreamID: WhisperStream] = [:]

    init(variant: WhisperModelVariant = .largeV3Turbo) {
        self.variant = variant
        descriptor = SpeechModelCatalog.descriptor(for: .whisper, whisperVariant: variant)
    }

    func warm(modelDirectory: URL, completion: @escaping @MainActor @Sendable (Result<Void, Error>) -> Void) {
        queue.async {
            let result = Result { try self.loadLocked(modelDirectory: modelDirectory) }
            DispatchQueue.main.async { completion(result) }
        }
    }

    func loadIfNeeded(modelDirectory: URL) throws {
        try queue.sync { try loadLocked(modelDirectory: modelDirectory) }
    }

    func unload() {
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
        let modelURL = modelDirectory.appendingPathComponent(variant.modelFileName)
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
        guard var state = streams[stream] else { throw NativeError.unavailable("The Whisper session has already ended.") }
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
        guard var state = streams[stream] else {
            audioLock.unlock()
            onFailure("The Whisper session has already ended.")
            return
        }
        state.samples.append(contentsOf: copy)
        streams[stream] = state
        audioLock.unlock()
    }

    func transcribe(
        stream: SpeechStreamID,
        completion: @escaping @MainActor @Sendable (Result<[SpeechLine], Error>) -> Void
    ) {
        queue.async {
            guard let context = self.context else {
                DispatchQueue.main.async { completion(.failure(NativeError.unavailable("The Whisper model is not ready."))) }
                return
            }
            self.audioLock.lock()
            guard var state = self.streams[stream] else {
                self.audioLock.unlock()
                DispatchQueue.main.async { completion(.failure(NativeError.unavailable("The Whisper session has already ended."))) }
                return
            }
            let changedEnough = state.samples.count - state.lastDecodedSampleCount >= self.updateStrideSamples
            guard changedEnough else {
                let lines = state.lines()
                self.audioLock.unlock()
                DispatchQueue.main.async { completion(.success(lines)) }
                return
            }
            state.lastDecodedSampleCount = state.samples.count
            let samples = state.samples
            let generation = state.generation
            self.streams[stream] = state
            self.audioLock.unlock()

            let result = Result { try self.transcribeLocked(context: context, samples: samples) }
            self.audioLock.lock()
            guard var current = self.streams[stream], current.generation == generation else {
                self.audioLock.unlock()
                DispatchQueue.main.async { completion(result.map { _ in [] }) }
                return
            }
            if case let .success(text) = result { current.latestText = text }
            let lines = current.lines()
            self.streams[stream] = current
            self.audioLock.unlock()
            DispatchQueue.main.async { completion(result.map { _ in lines }) }
        }
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
            guard let state = self.streams.removeValue(forKey: stream) else {
                self.audioLock.unlock()
                DispatchQueue.main.async { completion(.failure(NativeError.unavailable("The Whisper session has already ended."))) }
                return
            }
            self.audioLock.unlock()
            let result = Result { try self.transcribeLocked(context: context, samples: state.samples) }
            DispatchQueue.main.async { completion(result.map { text in
                text.isEmpty ? [] : [SpeechLine(
                    id: 1, start: 0, end: Double(state.samples.count) / 16_000, text: text, complete: true
                )]
            }) }
        }
    }

    func finishSynchronously(stream: SpeechStreamID) throws -> [SpeechLine] {
        try queue.sync {
            guard let context else { throw NativeError.unavailable("The Whisper model is not ready.") }
            audioLock.lock()
            guard let state = streams.removeValue(forKey: stream) else {
                audioLock.unlock()
                throw NativeError.unavailable("The Whisper session has already ended.")
            }
            audioLock.unlock()
            let text = try transcribeLocked(context: context, samples: state.samples)
            guard !text.isEmpty else { return [] }
            return [SpeechLine(
                id: 1, start: 0, end: Double(state.samples.count) / 16_000, text: text, complete: true
            )]
        }
    }

    func cancel(stream: SpeechStreamID) {
        audioLock.lock()
        streams.removeValue(forKey: stream)
        audioLock.unlock()
    }

    private func transcribeLocked(context: OpaquePointer, samples: [Float]) throws -> String {
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
        let status = "en".withCString { language in
            parameters.language = language
            return samples.withUnsafeBufferPointer { audio in
                guard let baseAddress = audio.baseAddress else { return Int32(-1) }
                return whisper_full(context, parameters, baseAddress, Int32(audio.count))
            }
        }
        guard status == 0 else { throw NativeError.unavailable("Whisper could not transcribe the current phrase.") }
        let count = Int(whisper_full_n_segments(context))
        let segments = (0..<count).compactMap { index -> String? in
            guard let value = whisper_full_get_segment_text(context, Int32(index)) else { return nil }
            return String(cString: value).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return TranscriptLedger.join(segments)
    }
}

private extension WhisperModelVariant {
    var modelFileName: String {
        switch self {
        case .largeV3Turbo: "ggml-large-v3-turbo.bin"
        case .largeV3: "ggml-large-v3.bin"
        }
    }
}
