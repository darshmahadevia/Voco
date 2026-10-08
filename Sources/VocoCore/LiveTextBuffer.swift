import Foundation

public enum LiveTextError: Error, Equatable { case changed, invalidRange }

public struct LiveTextPlan: Sendable {
    public let range: NSRange
    public let replacement: String
    public let document: String
    public let selection: NSRange
    fileprivate let transcript: String
}

public struct LiveTextBuffer: Sendable {
    private var document: String
    private var selection: NSRange
    private let start: Int
    private var originalSelectionLength: Int
    private var transcript = ""

    public init(document: String, selection: NSRange) throws {
        let units = Array(document.utf16)
        guard selection.location >= 0, selection.length >= 0,
              selection.location <= units.count,
              selection.length <= units.count - selection.location,
              Self.isUTF16Boundary(selection.location, in: units),
              Self.isUTF16Boundary(selection.location + selection.length, in: units)
        else { throw LiveTextError.invalidRange }
        self.document = document
        self.selection = selection
        self.start = selection.location
        self.originalSelectionLength = selection.length
    }

    public func plan(text: String, document current: String, selection caret: NSRange) throws -> LiveTextPlan? {
        guard Self.hasSameUTF16(current, document), caret == selection else { throw LiveTextError.changed }
        guard !Self.hasSameUTF16(text, transcript) else { return nil }
        let old = Array(transcript), new = Array(text)
        var prefix = 0
        while prefix < min(old.count, new.count), Self.hasSameScalars(old[prefix], new[prefix]) { prefix += 1 }
        var suffix = 0
        while suffix < min(old.count, new.count) - prefix,
              Self.hasSameScalars(old[old.count - suffix - 1], new[new.count - suffix - 1]) { suffix += 1 }
        let prefixLength = String(old.prefix(prefix)).utf16.count
        let suffixLength = String(old.suffix(suffix)).utf16.count
        let range = NSRange(location: start + prefixLength,
                            length: originalSelectionLength + transcript.utf16.count - prefixLength - suffixLength)
        let replacement = String(new[prefix..<(new.count - suffix)])
        let updated = (document as NSString).replacingCharacters(in: range, with: replacement)
        return LiveTextPlan(range: range, replacement: replacement, document: updated,
                            selection: NSRange(location: start + text.utf16.count, length: 0), transcript: text)
    }

    public mutating func accept(_ plan: LiveTextPlan, document: String, selection: NSRange) throws {
        guard Self.hasSameUTF16(document, plan.document), selection == plan.selection else { throw LiveTextError.changed }
        self.document = document
        self.selection = selection
        transcript = plan.transcript
        originalSelectionLength = 0
    }

    private static func hasSameUTF16(_ lhs: String, _ rhs: String) -> Bool {
        lhs.utf16.elementsEqual(rhs.utf16)
    }

    private static func hasSameScalars(_ lhs: Character, _ rhs: Character) -> Bool {
        lhs.unicodeScalars.elementsEqual(rhs.unicodeScalars)
    }

    private static func isUTF16Boundary(_ offset: Int, in units: [UInt16]) -> Bool {
        guard offset > 0, offset < units.count else { return true }
        let previous = units[offset - 1]
        let next = units[offset]
        return !(0xD800...0xDBFF).contains(previous) || !(0xDC00...0xDFFF).contains(next)
    }
}
