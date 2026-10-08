import Foundation

public struct Transcript: Sendable {
    private struct Segment: Sendable {
        var start: Double
        var end: Double
        var text: String
        var isFinal: Bool
    }

    private var segments: [Segment] = []

    public init() {}

    public mutating func update(start: Double, end: Double, text: String, isFinal: Bool) {
        guard start.isFinite, end.isFinite, end >= start else { return }
        if !isFinal && segments.contains(where: {
            $0.isFinal && ($0.start == start || ($0.start < end && start < $0.end))
        }) { return }
        segments.removeAll {
            $0.start == start || ($0.start < end && start < $0.end)
        }
        segments.append(Segment(start: start, end: end, text: text, isFinal: isFinal))
        segments.sort { $0.start < $1.start }
    }

    public var text: String { join(segments.map(\.text)) }
    public var finalText: String { join(segments.filter(\.isFinal).map(\.text)) }
    public var hasProvisionalText: Bool { segments.contains { !$0.isFinal && !$0.text.isEmpty } }
    public var latestEnd: Double { segments.map(\.end).max() ?? 0 }

    public func text(after time: Double) -> String {
        join(segments.filter { $0.end > time }.map(\.text))
    }

    public func finalized(after time: Double) -> (text: String, end: Double) {
        let pending = segments.filter { $0.isFinal && $0.end > time }
        return (join(pending.map(\.text)), pending.map(\.end).max() ?? time)
    }

    private func join(_ parts: [String]) -> String {
        parts.reduce(into: "") { result, part in
            if let last = result.last, let first = part.first,
               !last.isWhitespace, !first.isWhitespace,
               !".,!?;:)".contains(first) {
                result += " "
            }
            result += part
        }.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
