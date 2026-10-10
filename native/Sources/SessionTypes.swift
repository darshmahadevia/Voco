import Foundation

enum SpeechModelID: String, Codable, CaseIterable, Sendable, Identifiable {
    case moonshine
    case parakeet
    case whisper

    var id: String { rawValue }
}

struct SpeechModelDescriptor: Identifiable, Codable, Sendable {
    let id: SpeechModelID
    let name: String
    let modelVersion: String
    let language: String
    let license: String

    var engineVersion: String {
        switch id {
        case .moonshine: "moonshine-voice 0.1.5"
        case .parakeet: "FluidAudio 0.9.1"
        case .whisper: "whisper.cpp 1.9.5"
        }
    }
}

struct SpeechStreamID: Hashable, Sendable {
    let rawValue: UUID

    init(rawValue: UUID = UUID()) { self.rawValue = rawValue }
}

struct SpeechLine: Sendable {
    let id: UInt64
    let start: Double
    let end: Double
    let text: String
    let complete: Bool
}

protocol SpeechEngine: AnyObject, Sendable {
    var descriptor: SpeechModelDescriptor { get }
    func warm(modelDirectory: URL, completion: @escaping @MainActor @Sendable (Result<Void, Error>) -> Void)
    func loadIfNeeded(modelDirectory: URL) throws
    func unload()
    func openStream() throws -> SpeechStreamID
    func addAudio(_ samples: UnsafeBufferPointer<Float>, to stream: SpeechStreamID) throws
    func enqueueAudio(
        _ samples: UnsafeBufferPointer<Float>,
        to stream: SpeechStreamID,
        onFailure: @escaping @Sendable (String) -> Void
    )
    func transcribe(
        stream: SpeechStreamID,
        completion: @escaping @MainActor @Sendable (Result<[SpeechLine], Error>) -> Void
    )
    func finish(
        stream: SpeechStreamID,
        completion: @escaping @MainActor @Sendable (Result<[SpeechLine], Error>) -> Void
    )
    func finishSynchronously(stream: SpeechStreamID) throws -> [SpeechLine]
    func cancel(stream: SpeechStreamID)
}
