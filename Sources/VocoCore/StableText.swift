import Foundation

public struct StableText: Sendable {
    public private(set) var text = ""
    private var words: [String] = []
    private var stableSince: [TimeInterval] = []
    private var committedWords: [String] = []
    private let delay: TimeInterval
    private let tailDelay: TimeInterval

    public init(delay: TimeInterval = 0.18, tailDelay: TimeInterval = 0.36) {
        self.delay = delay
        self.tailDelay = tailDelay
    }

    public mutating func update(
        _ hypothesis: String, confirmedWordCount: Int = 0, final: Bool = false, now: TimeInterval
    ) {
        let next = hypothesis.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !next.isEmpty else {
            words = []
            stableSince = []
            return
        }
        let boundary = mappedBoundary(in: next)
        appendTrailingPunctuation(from: next, boundary: boundary)
        var common = 0
        while common < min(words.count, next.count),
              words[common].utf16.elementsEqual(next[common].utf16) { common += 1 }
        stableSince = Array(stableSince.prefix(common)) + Array(repeating: now, count: next.count - common)
        words = next
        let confirmed = min(next.count, max(0, confirmedWordCount))
        var end = boundary
        while end < next.count {
            let wait = end < next.count - 1 ? delay : next.count == 1 ? max(delay, tailDelay) : .infinity
            guard final || end < confirmed || now - stableSince[end] >= wait else { break }
            end += 1
        }
        guard end > boundary else { return }
        let addition = next[boundary..<end].joined(separator: " ")
        if !text.isEmpty, let first = addition.first, !".,!?;:)".contains(first) { text += " " }
        text += addition
        committedWords = Array(next.prefix(end))
    }

    private mutating func appendTrailingPunctuation(from next: [String], boundary: Int) {
        guard let previous = committedWords.last, boundary > 0 else { return }
        let revised = next[boundary - 1]
        guard revised.lowercased().hasPrefix(previous.lowercased()) else { return }
        let suffix = String(revised.dropFirst(previous.count))
        guard !suffix.isEmpty, suffix.unicodeScalars.allSatisfy(CharacterSet.punctuationCharacters.contains) else { return }
        text += suffix
        committedWords[committedWords.count - 1] = revised
    }

    private func mappedBoundary(in next: [String]) -> Int {
        guard !committedWords.isEmpty else { return 0 }
        let consumed = committedWords.count
        let old = committedWords.map(Self.matchingWord)
        let new = next.map(Self.matchingWord)
        if old.count <= new.count, old.elementsEqual(new.prefix(old.count)) { return old.count }
        // Align revisions with words already queued. Edits behind this boundary cannot change output.
        var costs = Array(0...new.count)
        for (index, word) in old.enumerated() {
            var row = Array(repeating: 0, count: new.count + 1)
            row[0] = index + 1
            for column in 1...new.count {
                row[column] = min(costs[column] + 1, row[column - 1] + 1,
                                  costs[column - 1] + (word == new[column - 1] ? 0 : 1))
            }
            costs = row
        }
        return (0...new.count).min {
            if costs[$0] != costs[$1] { return costs[$0] < costs[$1] }
            return abs($0 - consumed) < abs($1 - consumed)
        } ?? 0
    }

    private static func matchingWord(_ word: String) -> String {
        word.trimmingCharacters(in: .punctuationCharacters).lowercased()
    }
}

public enum LiveTextDelivery {
    public static let pollInterval: Duration = .milliseconds(120)
    public static let interval: Duration = .milliseconds(8)

    public static func nextChunk(in remaining: String) -> String {
        let count = remaining.count
        let size = count > 80 ? 16 : count > 24 ? 8 : 4
        return String(remaining.prefix(size))
    }
}
