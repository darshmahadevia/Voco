import AVFoundation
import Foundation
import Moonshine

final class MoonshineEngine: SpeechEngine, @unchecked Sendable {
    private let queue = DispatchQueue(label: "org.vocoapp.Voco.moonshine", qos: .userInitiated)
    private let audioLock = NSLock()
    private var pendingAudio = 0
    private var acceptingAudioStreams = Set<SpeechStreamID>()
    private let maximumQueuedAudioChunks = 128
    private var transcriber: Int32 = -1
    private var modelPath: String?
    private var liveStreams = Set<Int32>()
    private var streamHandles: [SpeechStreamID: Int32] = [:]

    func warm(modelDirectory: URL, completion: @escaping @MainActor @Sendable (Result<Void, Error>) -> Void) {
        queue.async {
            do {
                try self.loadLocked(modelDirectory: modelDirectory)
                DispatchQueue.main.async { completion(.success(())) }
            } catch {
                DispatchQueue.main.async { completion(.failure(error)) }
            }
        }
    }

    func unload() {
        queue.sync {
            guard transcriber >= 0 else { return }
            for stream in liveStreams { _ = moonshine_free_stream(transcriber, stream) }
            liveStreams.removeAll()
            streamHandles.removeAll()
            audioLock.lock()
            acceptingAudioStreams.removeAll()
            audioLock.unlock()
            moonshine_free_transcriber(transcriber)
            transcriber = -1
            modelPath = nil
        }
    }

    private func loadLocked(modelDirectory: URL) throws {
        if transcriber >= 0, modelPath == modelDirectory.path { return }
        if transcriber >= 0 {
            moonshine_free_transcriber(transcriber)
            transcriber = -1
        }
        let handle = modelDirectory.path.withCString { path in
            moonshine_load_transcriber_from_files(path, 5, nil, 0, MOONSHINE_HEADER_VERSION)
        }
        guard handle >= 0 else { throw Self.error(handle, prefix: "Moonshine could not load the speech model.") }
        transcriber = handle
        modelPath = modelDirectory.path
    }

    func openStream() throws -> SpeechStreamID {
        try queue.sync {
            guard transcriber >= 0 else { throw NativeError.unavailable("The Moonshine model is not ready.") }
            let stream = moonshine_create_stream(transcriber, 0)
            guard stream >= 0 else { throw Self.error(stream, prefix: "Moonshine could not start a dictation session.") }
            let id = SpeechStreamID()
            let result = moonshine_start_stream(transcriber, stream)
            guard result == 0 else {
                moonshine_free_stream(transcriber, stream)
                throw Self.error(result, prefix: "Moonshine could not start a dictation session.")
            }
            liveStreams.insert(stream)
            streamHandles[id] = stream
            audioLock.lock()
            acceptingAudioStreams.insert(id)
            audioLock.unlock()
            return id
        }
    }

    func addAudio(_ samples: UnsafeBufferPointer<Float>, to stream: SpeechStreamID) throws {
        guard let baseAddress = samples.baseAddress, !samples.isEmpty else { return }
        try queue.sync {
            guard let handle = streamHandles[stream], liveStreams.contains(handle), transcriber >= 0 else {
                throw NativeError.unavailable("The Moonshine session has already ended.")
            }
            let result = moonshine_transcribe_add_audio_to_stream(
                transcriber, handle, baseAddress, UInt64(samples.count), 16_000, 0
            )
            guard result == 0 else { throw Self.error(result, prefix: "Moonshine could not accept microphone audio.") }
        }
    }

    func enqueueAudio(
        _ samples: UnsafeBufferPointer<Float>,
        to stream: SpeechStreamID,
        onFailure: @escaping @Sendable (String) -> Void
    ) {
        guard !samples.isEmpty else { return }
        audioLock.lock()
        guard acceptingAudioStreams.contains(stream), pendingAudio < maximumQueuedAudioChunks else {
            audioLock.unlock()
            onFailure("Microphone audio is arriving faster than the speech engine can process it. Stop dictation and try again.")
            return
        }
        pendingAudio += 1
        audioLock.unlock()

        let copy = Array(samples)
        queue.async {
            defer {
                self.audioLock.lock()
                self.pendingAudio -= 1
                self.audioLock.unlock()
            }
            guard self.transcriber >= 0, let handle = self.streamHandles[stream], self.liveStreams.contains(handle) else { return }
            let result = copy.withUnsafeBufferPointer { samples -> Int32 in
                guard let baseAddress = samples.baseAddress else { return 0 }
                return moonshine_transcribe_add_audio_to_stream(
                    self.transcriber, handle, baseAddress, UInt64(samples.count), 16_000, 0
                )
            }
            if result != 0 {
                let error = Self.error(result, prefix: "Moonshine could not accept microphone audio.").localizedDescription
                onFailure(error)
            }
        }
    }

    func finish(
        stream: SpeechStreamID,
        completion: @escaping @MainActor @Sendable (Result<[SpeechLine], Error>) -> Void
    ) {
        audioLock.lock()
        acceptingAudioStreams.remove(stream)
        audioLock.unlock()
        queue.async {
            let result = Result {
                guard let handle = self.streamHandles.removeValue(forKey: stream), self.liveStreams.remove(handle) != nil else {
                    throw NativeError.unavailable("The Moonshine session has already ended.")
                }
                let stopped = moonshine_stop_stream(self.transcriber, handle)
                defer { _ = moonshine_free_stream(self.transcriber, handle) }
                guard stopped == 0 else {
                    throw Self.error(stopped, prefix: "Moonshine could not finish the current phrase.")
                }
                return try self.transcribeLocked(stream: handle)
            }
            DispatchQueue.main.async { completion(result) }
        }
    }

    func cancel(stream: SpeechStreamID) {
        audioLock.lock()
        acceptingAudioStreams.remove(stream)
        audioLock.unlock()
        queue.async {
            guard let handle = self.streamHandles.removeValue(forKey: stream), self.liveStreams.remove(handle) != nil,
                  self.transcriber >= 0 else { return }
            _ = moonshine_stop_stream(self.transcriber, handle)
            _ = moonshine_free_stream(self.transcriber, handle)
        }
    }

    private func transcribeLocked(stream: Int32) throws -> [SpeechLine] {
        guard transcriber >= 0 else { throw NativeError.unavailable("The Moonshine model is not ready.") }
        var transcript: UnsafeMutablePointer<transcript_t>?
        let result = moonshine_transcribe_stream(transcriber, stream, UInt32(MOONSHINE_FLAG_FORCE_UPDATE), &transcript)
        guard result == 0, let transcript else {
            throw Self.error(result, prefix: "Moonshine could not transcribe the current phrase.")
        }
        let lineCount = Int(transcript.pointee.line_count)
        guard lineCount == 0 || transcript.pointee.lines != nil else {
            throw NativeError.unavailable("Moonshine returned an invalid transcript.")
        }
        guard let lines = transcript.pointee.lines else { return [] }
        return (0..<lineCount).map { index in
            let line = lines[index]
            return SpeechLine(
                text: line.text.map(String.init(cString:)) ?? "",
                complete: line.is_complete != 0
            )
        }
    }

    private static func error(_ code: Int32, prefix: String) -> NativeError {
        let detail = String(cString: moonshine_error_to_string(code))
        return .unavailable("\(prefix) \(detail)")
    }
}

@MainActor
final class NativeAudioInput {
    private let engine: AVAudioEngine
    private var hasTap = false
    private var callbacks = DispatchGroup()

    init() { engine = AVAudioEngine() }

    func start(
        engine: any SpeechEngine,
        stream: SpeechStreamID,
        onSpeech: @escaping @MainActor () -> Void,
        onLevel: @escaping @MainActor @Sendable (Double, [Double]) -> Void = { _, _ in },
        onFailure: @escaping @MainActor (String) -> Void
    ) throws {
        let input = self.engine.inputNode
        let sourceFormat = input.outputFormat(forBus: 0)
        guard sourceFormat.sampleRate > 0, sourceFormat.channelCount > 0,
              let targetFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false),
              let converter = AVAudioConverter(from: sourceFormat, to: targetFormat)
        else { throw NativeError.unavailable("Voco could not prepare the microphone format.") }
        converter.primeMethod = .none
        let callback = NativeAudioTapProcessor(
            converter: converter,
            targetFormat: targetFormat,
            engine: engine,
            stream: stream,
            callbacks: callbacks,
            onSpeech: onSpeech,
            onLevel: onLevel,
            onFailure: onFailure
        )
        input.installTap(onBus: 0, bufferSize: 1024, format: sourceFormat, block: callback.tapBlock)
        hasTap = true
        self.engine.prepare()
        do { try self.engine.start() }
        catch {
            self.engine.inputNode.removeTap(onBus: 0)
            hasTap = false
            throw NativeError.unavailable("Voco could not start the microphone. \(error.localizedDescription)")
        }
    }

    func stop() {
        engine.stop()
        if hasTap {
            engine.inputNode.removeTap(onBus: 0)
            hasTap = false
        }
        callbacks.wait()
    }

}

final class NativeAudioTapProcessor {
    private let converter: AVAudioConverter
    private let targetFormat: AVAudioFormat
    private let engine: any SpeechEngine
    private let stream: SpeechStreamID
    private let callbacks: DispatchGroup
    private let onSpeech: @MainActor @Sendable () -> Void
    private let onLevel: @MainActor @Sendable (Double, [Double]) -> Void
    private let onFailure: @MainActor @Sendable (String) -> Void

    init(
        converter: AVAudioConverter,
        targetFormat: AVAudioFormat,
        engine: any SpeechEngine,
        stream: SpeechStreamID,
        callbacks: DispatchGroup,
        onSpeech: @escaping @MainActor @Sendable () -> Void,
        onLevel: @escaping @MainActor @Sendable (Double, [Double]) -> Void = { _, _ in },
        onFailure: @escaping @MainActor @Sendable (String) -> Void
    ) {
        self.converter = converter
        self.targetFormat = targetFormat
        self.engine = engine
        self.stream = stream
        self.callbacks = callbacks
        self.onSpeech = onSpeech
        self.onLevel = onLevel
        self.onFailure = onFailure
    }

    var tapBlock: AVAudioNodeTapBlock { process }

    private func process(_ buffer: AVAudioPCMBuffer, _: AVAudioTime) {
        callbacks.enter()
        defer { callbacks.leave() }
        do {
            guard let converted = try Self.convert(buffer, converter: converter, targetFormat: targetFormat) else { return }
            guard let samples = converted.floatChannelData?[0] else {
                throw NativeError.unavailable("Voco could not read microphone audio.")
            }
            let input = UnsafeBufferPointer(start: samples, count: Int(converted.frameLength))
            let meter = AudioMeter.measure(input, sampleRate: targetFormat.sampleRate)
            let onLevel = self.onLevel
            Task { @MainActor in onLevel(meter.level, meter.waveform) }
            if meter.rms > 0.008 {
                let onSpeech = self.onSpeech
                Task { @MainActor in onSpeech() }
            }
            engine.enqueueAudio(input, to: stream) { [onFailure] message in
                Task { @MainActor in onFailure(message) }
            }
        } catch {
            let message = error.localizedDescription
            let onFailure = self.onFailure
            Task { @MainActor in onFailure(message) }
        }
    }

    private nonisolated static func convert(
        _ buffer: AVAudioPCMBuffer,
        converter: AVAudioConverter,
        targetFormat: AVAudioFormat
    ) throws -> AVAudioPCMBuffer? {
        let capacity = AVAudioFrameCount(ceil(Double(buffer.frameLength) * targetFormat.sampleRate / buffer.format.sampleRate)) + 64
        guard let converted = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else { return nil }
        var supplied = false
        var conversionError: NSError?
        let status = converter.convert(to: converted, error: &conversionError) { _, inputStatus in
            guard !supplied else { inputStatus.pointee = .noDataNow; return nil }
            supplied = true
            inputStatus.pointee = .haveData
            return buffer
        }
        guard status != .error else { throw conversionError ?? NativeError.unavailable("Voco could not convert microphone audio.") }
        return converted
    }
}

enum NativeAudioFile {
    @MainActor
    static func feed(_ url: URL, to engine: any SpeechEngine, stream: SpeechStreamID) async throws {
        let file = try AVAudioFile(forReading: url)
        let sourceFormat = file.processingFormat
        guard sourceFormat.sampleRate > 0, sourceFormat.channelCount > 0,
              let targetFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false),
              let converter = AVAudioConverter(from: sourceFormat, to: targetFormat)
        else { throw NativeError.unavailable("Voco could not read the audio fixture format.") }
        converter.primeMethod = .none
        while file.framePosition < file.length {
            let sourceCount = AVAudioFrameCount(max(1, Int(sourceFormat.sampleRate / 20)))
            guard let source = AVAudioPCMBuffer(pcmFormat: sourceFormat, frameCapacity: sourceCount) else {
                throw NativeError.unavailable("Voco could not allocate an audio buffer.")
            }
            try file.read(into: source)
            if source.frameLength == 0 { break }
            let capacity = AVAudioFrameCount(ceil(Double(source.frameLength) * targetFormat.sampleRate / sourceFormat.sampleRate)) + 64
            guard let converted = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else {
                throw NativeError.unavailable("Voco could not allocate a converted audio buffer.")
            }
            var supplied = false
            var conversionError: NSError?
            let status = converter.convert(to: converted, error: &conversionError) { _, inputStatus in
                guard !supplied else { inputStatus.pointee = .noDataNow; return nil }
                supplied = true
                inputStatus.pointee = .haveData
                return source
            }
            guard status != .error else {
                throw NativeError.unavailable("Voco could not convert the audio fixture. \(conversionError?.localizedDescription ?? "")")
            }
            if let samples = converted.floatChannelData?[0] {
                let input = UnsafeBufferPointer(start: samples, count: Int(converted.frameLength))
                try engine.addAudio(input, to: stream)
            }
        }
    }
}
