import Foundation

enum SpeechModelID: String, Codable, CaseIterable, Sendable, Identifiable {
    case moonshine
    case parakeet
    case whisper

    var id: String { rawValue }
}

struct SpeechStreamID: Hashable, Sendable {
    let rawValue: UUID

    init(rawValue: UUID = UUID()) { self.rawValue = rawValue }
}

struct SpeechLine: Sendable {
    let text: String
    let complete: Bool
}

protocol SpeechEngine: AnyObject, Sendable {
    func warm(modelDirectory: URL, completion: @escaping @MainActor @Sendable (Result<Void, Error>) -> Void)
    func unload()
    func openStream() throws -> SpeechStreamID
    func addAudio(_ samples: UnsafeBufferPointer<Float>, to stream: SpeechStreamID) throws
    func enqueueAudio(
        _ samples: UnsafeBufferPointer<Float>,
        to stream: SpeechStreamID,
        onFailure: @escaping @Sendable (String) -> Void
    )
    func finish(
        stream: SpeechStreamID,
        completion: @escaping @MainActor @Sendable (Result<[SpeechLine], Error>) -> Void
    )
    func cancel(stream: SpeechStreamID)
}

// Diagnostics use the same asynchronous loading and finalization as dictation.
extension SpeechEngine {
    @MainActor
    func warm(modelDirectory: URL) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            warm(modelDirectory: modelDirectory) { continuation.resume(with: $0) }
        }
    }

    @MainActor
    func finish(stream: SpeechStreamID) async throws -> [SpeechLine] {
        try await withCheckedThrowingContinuation { continuation in
            finish(stream: stream) { continuation.resume(with: $0) }
        }
    }
}
