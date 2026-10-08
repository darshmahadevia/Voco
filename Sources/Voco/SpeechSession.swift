@preconcurrency import AVFoundation
import CoreMedia
import Speech
import VocoCore
import OSLog

enum VocoError: LocalizedError {
    case unavailable, microphone, audioFormat, audioConversion, timedOut

    var errorDescription: String? {
        switch self {
        case .unavailable: "English transcription is unavailable on this Mac."
        case .microphone: "Allow microphone access in System Settings, then try again."
        case .audioFormat: "No working microphone was found. Connect one and try again."
        case .audioConversion: "The microphone audio could not be processed. Try another input device."
        case .timedOut: "Transcription took too long. Your preview is still available to copy."
        }
    }
}

@MainActor
final class SpeechSession {
    private let transcriber: SpeechTranscriber
    private let analyzer: SpeechAnalyzer
    private let format: AVAudioFormat
    private let engine = AVAudioEngine()
    private var continuation: AsyncThrowingStream<AnalyzerInput, Error>.Continuation?
    private var analysisTask: Task<CMTime?, Error>?
    private var resultTask: Task<Void, Error>?
    private var hasTap = false
    private var transcript = Transcript()
    private let logger = Logger(subsystem: "org.utterapp.Utter", category: "Speech")
    private var startedAt: ContinuousClock.Instant?
    private var reportedFirstResult = false
    var currentTranscript: Transcript { transcript }

    private init(transcriber: SpeechTranscriber, analyzer: SpeechAnalyzer, format: AVAudioFormat) {
        self.transcriber = transcriber
        self.analyzer = analyzer
        self.format = format
    }

    static func prepare(onProgress: @escaping @MainActor (Double?) -> Void) async throws -> SpeechSession {
        guard SpeechTranscriber.isAvailable,
              let locale = await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: "en-US"))
        else { throw VocoError.unavailable }
        let transcriber = SpeechTranscriber(
            locale: locale,
            transcriptionOptions: [],
            reportingOptions: [.volatileResults, .fastResults],
            attributeOptions: [.audioTimeRange]
        )
        try await AssetInventory.reserve(locale: locale)
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            let progressTask = Task {
                while !Task.isCancelled {
                    onProgress(request.progress.fractionCompleted)
                    try? await Task.sleep(for: .milliseconds(200))
                }
            }
            defer { progressTask.cancel() }
            try await request.downloadAndInstall()
        }
        onProgress(nil)
        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber])
        else { throw VocoError.audioFormat }
        let analyzer = SpeechAnalyzer(
            modules: [transcriber],
            options: .init(priority: .userInitiated, modelRetention: .processLifetime)
        )
        try await analyzer.prepareToAnalyze(in: format)
        return SpeechSession(transcriber: transcriber, analyzer: analyzer, format: format)
    }

    func start(
        onUpdate: @escaping @MainActor (Transcript) -> Void,
        onSpeechActivity: @escaping @Sendable () -> Void = {},
        onFailure: @escaping @MainActor (String) -> Void
    ) throws {
        let input = engine.inputNode
        let sourceFormat = input.outputFormat(forBus: 0)
        guard sourceFormat.sampleRate > 0, sourceFormat.channelCount > 0,
              let converter = AVAudioConverter(from: sourceFormat, to: format)
        else { throw VocoError.audioFormat }
        converter.primeMethod = .none
        let (stream, continuation) = AsyncThrowingStream<AnalyzerInput, Error>.makeStream(
            bufferingPolicy: .bufferingOldest(128)
        )
        self.continuation = continuation
        input.installTap(
            onBus: 0, bufferSize: 1024, format: sourceFormat,
            block: Self.audioTap(converter: converter, format: format, continuation: continuation, onSpeechActivity: onSpeechActivity)
        )
        hasTap = true
        startedAt = .now
        consumeResults(onUpdate: onUpdate, onFailure: onFailure)
        analysisTask = Task {
            do { return try await analyzer.analyzeSequence(stream) }
            catch {
                if !Task.isCancelled { onFailure(error.localizedDescription) }
                throw error
            }
        }
        engine.prepare()
        try engine.start()
    }

    static func transcribeFile(_ url: URL) async throws -> String {
        let session = try await prepare { _ in }
        let file = try AVAudioFile(forReading: url)
        session.consumeResults { _ in }
        session.analysisTask = Task { try await session.analyzer.analyzeSequence(from: file) }
        do {
            return try await session.finish()
        } catch {
            await session.cancel()
            throw error
        }
    }

    static func transcribeStream(_ url: URL, onUpdate: @escaping @MainActor (Transcript) -> Void = { _ in }) async throws -> String {
        let session = try await prepare { _ in }
        let file = try AVAudioFile(forReading: url)
        let (stream, continuation) = AsyncThrowingStream<AnalyzerInput, Error>.makeStream()
        guard let converter = AVAudioConverter(from: file.processingFormat, to: session.format)
        else { throw VocoError.audioFormat }
        converter.primeMethod = .none
        let convert = audioTap(converter: converter, format: session.format, continuation: continuation)
        let start = ContinuousClock.now
        var firstResult = true
        session.consumeResults { transcript in
            onUpdate(transcript)
            if firstResult && !transcript.text.isEmpty {
                print("First live result: \(start.duration(to: .now))")
                firstResult = false
            }
        }
        session.analysisTask = Task { try await session.analyzer.analyzeSequence(stream) }
        do {
            while file.framePosition < file.length {
                let count = AVAudioFrameCount(file.processingFormat.sampleRate / 20)
                guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: count)
                else { throw VocoError.audioFormat }
                try file.read(into: buffer)
                convert(buffer, AVAudioTime(sampleTime: file.framePosition, atRate: file.processingFormat.sampleRate))
                try await Task.sleep(for: .milliseconds(50))
            }
            continuation.finish()
            let releasedAt = ContinuousClock.now
            let text = try await session.finish()
            print("Release to final: \(releasedAt.duration(to: .now))")
            return text
        } catch {
            continuation.finish()
            await session.cancel()
            throw error
        }
    }

    static func verifyPauses(_ url: URL) async throws {
        let session = try await prepare { _ in }
        let file = try AVAudioFile(forReading: url)
        let (stream, continuation) = AsyncThrowingStream<AnalyzerInput, Error>.makeStream()
        guard let converter = AVAudioConverter(from: file.processingFormat, to: session.format)
        else { throw VocoError.audioFormat }
        converter.primeMethod = .none
        let convert = audioTap(converter: converter, format: session.format, continuation: continuation)
        session.continuation = continuation
        session.consumeResults { _ in }
        session.analysisTask = Task { try await session.analyzer.analyzeSequence(stream) }
        func feed(silence: Bool) async throws {
            let count = AVAudioFrameCount(file.processingFormat.sampleRate / 20)
            let iterations = silence ? 30 : Int(ceil(Double(file.length) / Double(count)))
            if !silence { file.framePosition = 0 }
            for _ in 0..<iterations {
                guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: count)
                else { throw VocoError.audioFormat }
                if silence {
                    buffer.frameLength = count
                    for audioBuffer in UnsafeMutableAudioBufferListPointer(buffer.mutableAudioBufferList) {
                        if let data = audioBuffer.mData { memset(data, 0, Int(audioBuffer.mDataByteSize)) }
                    }
                } else { try file.read(into: buffer) }
                convert(buffer, AVAudioTime(sampleTime: 0, atRate: file.processingFormat.sampleRate))
                try await Task.sleep(for: .milliseconds(50))
            }
        }
        func words(_ text: String) -> [String] {
            text.split { !$0.isLetter }.map { $0.lowercased() }
        }
        do {
            try await feed(silence: false)
            try await feed(silence: true)
            let first = try await session.finalizePause().finalized(after: -1)
            guard !first.text.isEmpty else { throw VocoError.unavailable }
            print("Pause 1: \(first.text)")
            try await feed(silence: false)
            try await feed(silence: true)
            let second = try await session.finalizePause().finalized(after: first.end)
            guard words(second.text) == words(first.text) else { throw VocoError.unavailable }
            print("Pause 2: \(second.text)")
            let final = try await session.finishTranscript()
            guard final.finalized(after: second.end).text.isEmpty else { throw VocoError.unavailable }
            print("Two pause batches verified; stopping does not duplicate words")
        } catch {
            await session.cancel()
            throw error
        }
    }

    private func consumeResults(
        onUpdate: @escaping @MainActor (Transcript) -> Void,
        onFailure: @escaping @MainActor (String) -> Void = { _ in }
    ) {
        resultTask = Task {
            do {
                for try await result in transcriber.results {
                    if !reportedFirstResult, !result.text.characters.isEmpty, let startedAt {
                        reportedFirstResult = true
                        logger.notice("First result after microphone start: \(String(describing: startedAt.duration(to: .now)), privacy: .public)")
                    }
                    transcript.update(
                        start: result.range.start.seconds,
                        end: CMTimeRangeGetEnd(result.range).seconds,
                        text: String(result.text.characters),
                        isFinal: result.isFinal
                    )
                    onUpdate(transcript)
                }
            } catch {
                if !Task.isCancelled { onFailure(error.localizedDescription) }
                throw error
            }
        }
    }

    func finish() async throws -> String {
        try await finishTranscript().finalText
    }

    func finalizePause() async throws -> Transcript {
        guard transcript.hasProvisionalText else { return transcript }
        // Give natural final results a chance to arrive before forcing a phrase boundary.
        for _ in 0..<10 {
            try await Task.sleep(for: .milliseconds(20))
            if !transcript.hasProvisionalText { return transcript }
        }
        try await analyzer.finalize(through: nil)
        // Finalization publishes results; their consumer runs separately on the main actor.
        for _ in 0..<50 {
            await Task.yield()
            if !transcript.hasProvisionalText { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        return transcript
    }

    func finishTranscript() async throws -> Transcript {
        stopAudio()
        continuation?.finish()
        if let end = try await analysisTask?.value {
            try await analyzer.finalizeAndFinish(through: end)
        } else {
            await analyzer.cancelAndFinishNow()
        }
        try await resultTask?.value
        return transcript
    }

    func cancel() async {
        stopAudio()
        continuation?.finish()
        analysisTask?.cancel()
        resultTask?.cancel()
        await analyzer.cancelAndFinishNow()
    }

    private func stopAudio() {
        engine.stop()
        if hasTap {
            engine.inputNode.removeTap(onBus: 0)
            hasTap = false
        }
    }

    nonisolated private static func audioTap(
        converter: AVAudioConverter,
        format: AVAudioFormat,
        continuation: AsyncThrowingStream<AnalyzerInput, Error>.Continuation,
        onSpeechActivity: @escaping @Sendable () -> Void = {}
    ) -> AVAudioNodeTapBlock {
        { buffer, _ in
            let capacity = AVAudioFrameCount(ceil(Double(buffer.frameLength) * format.sampleRate / buffer.format.sampleRate)) + 32
            guard let converted = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity)
            else { continuation.finish(throwing: VocoError.audioConversion); return }
            var supplied = false
            var error: NSError?
            let status = converter.convert(to: converted, error: &error) { _, inputStatus in
                if supplied {
                    inputStatus.pointee = .noDataNow
                    return nil
                }
                supplied = true
                inputStatus.pointee = .haveData
                return buffer
            }
            if status == .error {
                continuation.finish(throwing: error ?? VocoError.audioConversion)
            } else if converted.frameLength > 0 {
                if let samples = converted.floatChannelData?[0] {
                    var energy: Float = 0
                    for index in 0..<Int(converted.frameLength) { energy += samples[index] * samples[index] }
                    if energy / Float(converted.frameLength) > 0.000064 { onSpeechActivity() }
                }
                if case .dropped = continuation.yield(AnalyzerInput(buffer: converted)) {
                    continuation.finish(throwing: VocoError.audioConversion)
                }
            }
        }
    }
}
