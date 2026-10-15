import CoreML
@preconcurrency import FluidAudio
import Foundation

private actor ParakeetRuntime {
    private var manager: SendableParakeetManager?
    private var modelPath: String?
    private var lastTranscription: Task<String, Error>?

    func load(from directory: URL) async throws {
        guard modelPath != directory.path || manager == nil else { return }
        if let lastTranscription { _ = try? await lastTranscription.value }
        manager = nil
        modelPath = nil

        let configuration = MLModelConfiguration()
        configuration.computeUnits = .cpuAndNeuralEngine
        let preprocessorConfiguration = MLModelConfiguration()
        preprocessorConfiguration.computeUnits = .cpuOnly
        let preprocessor = try MLModel(
            contentsOf: directory.appendingPathComponent("Preprocessor.mlmodelc"),
            configuration: preprocessorConfiguration
        )
        let encoder = try MLModel(
            contentsOf: directory.appendingPathComponent("Encoder.mlmodelc"),
            configuration: configuration
        )
        let decoder = try MLModel(
            contentsOf: directory.appendingPathComponent("Decoder.mlmodelc"),
            configuration: configuration
        )
        let joint = try MLModel(
            contentsOf: directory.appendingPathComponent("JointDecision.mlmodelc"),
            configuration: configuration
        )
        let vocabularyURL = directory.appendingPathComponent("parakeet_vocab.json")
        let vocabularyObject = try JSONSerialization.jsonObject(with: Data(contentsOf: vocabularyURL))
        guard let rawVocabulary = vocabularyObject as? [String: String] else {
            throw NativeError.unavailable("Parakeet's vocabulary file is invalid.")
        }
        var vocabulary: [Int: String] = [:]
        for (key, value) in rawVocabulary {
            guard let token = Int(key) else {
                throw NativeError.unavailable("Parakeet's vocabulary contains an invalid token ID.")
            }
            vocabulary[token] = value
        }
        guard !vocabulary.isEmpty else {
            throw NativeError.unavailable("Parakeet's vocabulary is empty.")
        }

        let models = AsrModels(
            encoder: encoder,
            preprocessor: preprocessor,
            decoder: decoder,
            joint: joint,
            configuration: configuration,
            vocabulary: vocabulary,
            version: .v2
        )
        let manager = AsrManager()
        try await manager.initialize(models: models)
        self.manager = SendableParakeetManager(manager)
        modelPath = directory.path
    }

    func transcribe(_ samples: [Float]) async throws -> String {
        guard let manager else { throw NativeError.unavailable("The Parakeet model is not ready.") }
        guard !samples.isEmpty else { return "" }
        let input = samples.count >= 16_000
            ? samples
            : samples + Array(repeating: 0, count: 16_000 - samples.count)
        let previous = lastTranscription
        let task = Task {
            if let previous { _ = try? await previous.value }
            return try await manager.transcribe(input)
        }
        lastTranscription = task
        return try await task.value
    }

    func unload() async {
        if let lastTranscription { _ = try? await lastTranscription.value }
        manager = nil
        modelPath = nil
        lastTranscription = nil
    }
}

private final class SendableParakeetManager: @unchecked Sendable {
    private let manager: AsrManager

    init(_ manager: AsrManager) { self.manager = manager }

    func transcribe(_ samples: [Float]) async throws -> String {
        try await manager.transcribe(samples, source: .microphone).text
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private struct ParakeetStream {
    var samples: [Float] = []
}

final class ParakeetEngine: SpeechEngine, @unchecked Sendable {
    private let runtime = ParakeetRuntime()
    private let queue = DispatchQueue(label: "org.vocoapp.Voco.parakeet.state", qos: .userInitiated)
    private var modelPath: String?
    private var streams: [SpeechStreamID: ParakeetStream] = [:]

    func warm(modelDirectory: URL, completion: @escaping @MainActor @Sendable (Result<Void, Error>) -> Void) {
        Task {
            do {
                try await runtime.load(from: modelDirectory)
                queue.sync { modelPath = modelDirectory.path }
                await completion(.success(()))
            } catch {
                await completion(.failure(error))
            }
        }
    }

    func unload() {
        let semaphore = DispatchSemaphore(value: 0)
        Task {
            await runtime.unload()
            semaphore.signal()
        }
        semaphore.wait()
        queue.sync {
            modelPath = nil
            streams.removeAll()
        }
    }

    func openStream() throws -> SpeechStreamID {
        try queue.sync {
            guard modelPath != nil else { throw NativeError.unavailable("The Parakeet model is not ready.") }
            let stream = SpeechStreamID()
            streams[stream] = ParakeetStream()
            return stream
        }
    }

    func addAudio(_ samples: UnsafeBufferPointer<Float>, to stream: SpeechStreamID) throws {
        guard !samples.isEmpty else { return }
        try queue.sync {
            guard var state = streams[stream] else { throw NativeError.unavailable("The Parakeet session has already ended.") }
            state.samples.append(contentsOf: samples)
            streams[stream] = state
        }
    }

    func enqueueAudio(
        _ samples: UnsafeBufferPointer<Float>,
        to stream: SpeechStreamID,
        onFailure: @escaping @Sendable (String) -> Void
    ) {
        guard !samples.isEmpty else { return }
        let copy = Array(samples)
        queue.async {
            guard var state = self.streams[stream] else { return }
            state.samples.append(contentsOf: copy)
            self.streams[stream] = state
        }
    }

    func finish(
        stream: SpeechStreamID,
        completion: @escaping @MainActor @Sendable (Result<[SpeechLine], Error>) -> Void
    ) {
        queue.async {
            guard let state = self.streams.removeValue(forKey: stream) else {
                DispatchQueue.main.async { completion(.failure(NativeError.unavailable("The Parakeet session has already ended."))) }
                return
            }
            Task {
                let result: Result<String, Error>
                do { result = .success(try await self.runtime.transcribe(state.samples)) }
                catch { result = .failure(error) }
                DispatchQueue.main.async {
                    guard case let .success(text) = result else { completion(result.map { _ in [] }); return }
                    completion(.success(text.isEmpty ? [] : [SpeechLine(
                        text: text, complete: true
                    )]))
                }
            }
        }
    }

    func cancel(stream: SpeechStreamID) {
        queue.async { self.streams.removeValue(forKey: stream) }
    }
}
