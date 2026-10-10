import Foundation

struct SessionIDGate {
    private(set) var current: UUID?

    mutating func begin(_ id: UUID) { current = id }
    mutating func invalidate() { current = nil }
    func accepts(_ id: UUID) -> Bool { current == id }
}

struct TranscriptLedger {
    private(set) var lines: [SpeechLine] = []
    var text: String { Self.join(lines.map(\.text)) }

    mutating func update(_ next: [SpeechLine]) {
        if !next.isEmpty { lines = next }
    }

    static func join(_ parts: [String]) -> String {
        parts.filter { !$0.isEmpty }.reduce(into: "") { result, part in
            if let last = result.last, let first = part.first,
               !last.isWhitespace, !first.isWhitespace,
               !".,!?;:)".contains(first) {
                result.append(" ")
            }
            result.append(part)
        }.trimmingCharacters(in: .whitespacesAndNewlines)
    }

}
