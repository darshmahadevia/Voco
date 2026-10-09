import Foundation

struct SessionIDGate {
    private(set) var current: UUID?

    mutating func begin(_ id: UUID) { current = id }
    mutating func invalidate() { current = nil }
    func accepts(_ id: UUID) -> Bool { current == id }
}

struct TranscriptLedger {
    private(set) var lines: [MoonshineLine] = []
    private var committedIDs = Set<UInt64>()
    private(set) var committedText = ""

    var pendingLines: [MoonshineLine] { lines.filter { !committedIDs.contains($0.id) } }
    var committablePrefix: [MoonshineLine] {
        pendingLines.prefix(while: \.complete).map { $0 }
    }
    var pendingText: String { Self.join(pendingLines.map(\.text)) }
    var livePendingText: String {
        Self.separate(committed: committedText, pending: pendingText)
    }
    var text: String { Self.join([committedText, pendingText]) }

    mutating func update(_ next: [MoonshineLine]) {
        if !next.isEmpty { lines = next }
    }

    func insertion(for requested: [MoonshineLine]) -> String {
        let selected = requested.filter { $0.complete && !committedIDs.contains($0.id) }
        let next = Self.join(selected.map(\.text))
        return Self.separate(committed: committedText, pending: next)
    }

    mutating func markCommitted(_ requested: [MoonshineLine]) {
        let selected = requested.filter { $0.complete && !committedIDs.contains($0.id) }
        let next = Self.join(selected.map(\.text))
        guard !next.isEmpty else { return }
        committedIDs.formUnion(selected.map(\.id))
        committedText = Self.join([committedText, next])
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

    private static func separate(committed: String, pending: String) -> String {
        guard !pending.isEmpty, !committed.isEmpty,
              let last = committed.last, let first = pending.first,
              !last.isWhitespace, !first.isWhitespace,
              !".,!?;:)".contains(first) else { return pending }
        return " " + pending
    }
}

