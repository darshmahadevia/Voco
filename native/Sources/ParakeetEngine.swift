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
    var latestText = ""
    var lastDecodedSampleCount = 0
    var inferenceRunning = false
    var generation = UUID()

    var lines: [SpeechLine] {
        guard !latestText.isEmpty else { return [] }
        return [SpeechLine(text: latestText, complete: false)]
    }
}

final class ParakeetEngine: SpeechEngine, @unchecked Sendable {
    let descriptor: SpeechModelDescriptor = SpeechModelCatalog.descriptor(for: .parakeet)
    private let runtime = ParakeetRuntime()
    private let queue = DispatchQueue(label: "org.vocoapp.Voco.parakeet.state", qos: .userInitiated)
    private var modelPath: String?
    private var streams: [SpeechStreamID: ParakeetStream] = [:]
    private let updateStrideSamples = 32_000

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

    func loadIfNeeded(modelDirectory: URL) throws {
        if queue.sync(execute: { modelPath == modelDirectory.path }) { return }
        let semaphore = DispatchSemaphore(value: 0)
        let result = ParakeetLoadResult()
        Task {
            do {
                try await runtime.load(from: modelDirectory)
                result.finish(.success(()))
            } catch {
                result.finish(.failure(error))
            }
            semaphore.signal()
        }
        semaphore.wait()
        try result.value()
        queue.sync { modelPath = modelDirectory.path }
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

    func transcribe(
        stream: SpeechStreamID,
        completion: @escaping @MainActor @Sendable (Result<[SpeechLine], Error>) -> Void
    ) {
        queue.async {
            guard var state = self.streams[stream] else {
                DispatchQueue.main.async { completion(.failure(NativeError.unavailable("The Parakeet session has already ended."))) }
                return
            }
            let changedEnough = state.samples.count - state.lastDecodedSampleCount >= self.updateStrideSamples
            guard !state.inferenceRunning, changedEnough else {
                let lines = state.lines
                DispatchQueue.main.async { completion(.success(lines)) }
                return
            }
            state.inferenceRunning = true
            state.lastDecodedSampleCount = state.samples.count
            let generation = state.generation
            let samples = state.samples
            self.streams[stream] = state
            Task {
                let result: Result<String, Error>
                do { result = .success(try await self.runtime.transcribe(samples)) }
                catch { result = .failure(error) }
                self.queue.async {
                    guard var current = self.streams[stream], current.generation == generation else {
                        DispatchQueue.main.async { completion(.success([])) }
                        return
                    }
                    current.inferenceRunning = false
                    switch result {
                    case let .success(text): current.latestText = text
                    case .failure: break
                    }
                    self.streams[stream] = current
                    let lines = current.lines
                    DispatchQueue.main.async { completion(result.map { _ in lines }) }
                }
            }
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

    func finishSynchronously(stream: SpeechStreamID) throws -> [SpeechLine] {
        let state = try queue.sync { () throws -> ParakeetStream in
            guard let state = streams.removeValue(forKey: stream) else {
                throw NativeError.unavailable("The Parakeet session has already ended.")
            }
            return state
        }
        let semaphore = DispatchSemaphore(value: 0)
        let result = ParakeetTranscriptResult()
        Task {
            do { result.finish(.success(try await runtime.transcribe(state.samples))) }
            catch { result.finish(.failure(error)) }
            semaphore.signal()
        }
        semaphore.wait()
        let text = try result.value()
        guard !text.isEmpty else { return [] }
        return [SpeechLine(text: text, complete: true)]
    }

    func cancel(stream: SpeechStreamID) {
        queue.async { self.streams.removeValue(forKey: stream) }
    }
}

private final class ParakeetLoadResult: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Result<Void, Error>?

    func finish(_ value: Result<Void, Error>) { lock.lock(); stored = value; lock.unlock() }
    func value() throws { lock.lock(); defer { lock.unlock() }; try stored!.get() }
}

private final class ParakeetTranscriptResult: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Result<String, Error>?

    func finish(_ value: Result<String, Error>) { lock.lock(); stored = value; lock.unlock() }
    func value() throws -> String { lock.lock(); defer { lock.unlock() }; return try stored!.get() }
}
