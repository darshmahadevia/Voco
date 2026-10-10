import AppKit
import ApplicationServices
import Foundation
import VocoCore

@MainActor
func verifyEmptyRichEditor() async throws {
    guard let captured = FocusTarget.capture() else { throw InsertionError.focusUnavailable }
    let target = try await captured.resolved()
    let element = try target.validate()
    let baseline = try LiveTextWriter.snapshot(element)
    guard ["", "\n"].contains(baseline.text), baseline.selection == NSRange(location: 0, length: 0)
    else { throw InsertionError.focusChanged }
    let clipboardCount = NSPasteboard.general.changeCount
    let writer = try LiveTextWriter(target: target)
    var words = ""
    for character in "Goodbye" {
        try await writer.appendInEditor(String(character))
        words.append(character)
        let actual = try LiveTextWriter.snapshot(element)
        guard actual.text == words || (words.isEmpty && actual.text == "\n"),
              actual.selection == NSRange(location: words.utf16.count, length: 0),
              NSPasteboard.general.changeCount == clipboardCount
        else { throw InsertionError.unavailable }
        print("Verified empty rich editor append: \(words.debugDescription)")
    }
    for character in " again." { try await writer.appendInEditor(String(character)) }
    guard try LiveTextWriter.snapshot(element).text == "Goodbye again." else { throw InsertionError.unavailable }
    let document = try LiveTextWriter.snapshot(element).text
    try await writer.setEditorSelection(NSRange(location: 0, length: 0), document: document,
                                        previous: NSRange(location: document.utf16.count, length: 0))
    do {
        try await writer.appendInEditor("Unsafe")
        throw InsertionError.unavailable
    } catch InsertionError.focusChanged {}
    guard try LiveTextWriter.snapshot(element).text == document,
          NSPasteboard.general.changeCount == clipboardCount else { throw InsertionError.unavailable }
    print("Empty rich editor checks: PASS")
}

@MainActor
func verifyLiveInsertion(expected: String, audioFixture: URL? = nil, engine: (any SpeechEngine)? = nil) async throws {
    guard let captured = FocusTarget.capture() else { throw InsertionError.focusUnavailable }
    let target = try await captured.resolved()
    let element = try target.validate()
    let webEditor = FocusTarget.isWebEditor(element)
    func sameEditorText(_ actual: String, _ expected: String) -> Bool {
        let actual = webEditor ? actual.replacingOccurrences(of: "\u{00A0}", with: " ") : actual
        let expected = webEditor ? expected.replacingOccurrences(of: "\u{00A0}", with: " ") : expected
        return actual.utf16.elementsEqual(expected.utf16)
    }
    func snapshot() throws -> (String, NSRange) {
        var text: CFTypeRef?, selected: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &text) == .success,
              let text = text as? String,
              AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &selected) == .success,
              let selected, CFGetTypeID(selected) == AXValueGetTypeID() else { throw InsertionError.unavailable }
        var range = CFRange()
        guard AXValueGetValue(selected as! AXValue, .cfRange, &range) else { throw InsertionError.unavailable }
        return (text, NSRange(location: range.location, length: range.length))
    }
    let (baseline, selection) = try snapshot()
    guard baseline.utf16.elementsEqual(expected.utf16) else { throw InsertionError.focusChanged }
    let clipboard = (NSPasteboard.general.pasteboardItems ?? []).map { item in
        item.types.map { ($0.rawValue, item.data(forType: $0)) }
    }
    let changeCount = NSPasteboard.general.changeCount
    func checkClipboard() throws {
        let now = (NSPasteboard.general.pasteboardItems ?? []).map { item in
            item.types.map { ($0.rawValue, item.data(forType: $0)) }
        }
        guard now.count == clipboard.count, NSPasteboard.general.changeCount == changeCount else { throw InsertionError.unavailable }
        for (before, after) in zip(clipboard, now) {
            guard before.count == after.count else { throw InsertionError.unavailable }
            for (left, right) in zip(before, after) {
                guard left.0 == right.0, left.1 == right.1 else { throw InsertionError.unavailable }
            }
        }
    }
    let writer = try LiveTextWriter(target: target)
    let start = selection.location + selection.length
    var inserted = ""
    func appendRapidly(_ desired: String) async throws {
        guard desired.utf16.starts(with: inserted.utf16) else { throw InsertionError.unavailable }
        while inserted != desired {
            let started = ContinuousClock.now
            let chunk = LiveTextDelivery.nextChunk(in: String(desired.dropFirst(inserted.count)))
            try await writer.appendInEditor(chunk)
            inserted += chunk
            let (actual, caret) = try snapshot()
            let document = (baseline as NSString).replacingCharacters(in: NSRange(location: start, length: 0), with: inserted)
            guard sameEditorText(actual, document),
                  caret == (selection.length > 0 ? selection : NSRange(location: start + inserted.utf16.count, length: 0))
            else { throw InsertionError.unavailable }
            try checkClipboard()
            let pause = LiveTextDelivery.interval - started.duration(to: .now)
            if pause > .zero { try await Task.sleep(for: pause) }
        }
    }
    var stable = StableText()
    let long = String(repeating: "Long 🍦 phrase. ", count: 8)
    let hypotheses = ["I scream", "Ice cream. 🍦", "Ice cream. 🍦 and coffee.", "Ice cream. 🍦", "", long, long, long]
    for (index, words) in hypotheses.enumerated() {
        let final = index == hypotheses.count - 1
        let time = index < 6 ? Double(index) * 0.03 : 0.36 + Double(index - 6) * 0.03
        stable.update(words, final: final, now: time)
        let desired = stable.text.isEmpty ? "" : " " + stable.text + (final ? " " : "")
        try await appendRapidly(desired)
        print("Verified buffered hypothesis and append-only input: \(words.debugDescription)")
    }
    try await appendRapidly(inserted + " Next phrase.")
    let continued = (baseline as NSString).replacingCharacters(in: NSRange(location: start, length: 0), with: inserted)
    var final = continued
    if let audioFixture, let engine {
        var partials = 0
        var ledger = TranscriptLedger()
        var speech = StableText()
        let previous = inserted
        let finalLines = try await transcribeStreamingFile(audioFixture, engine: engine) { lines in
            ledger.update(lines)
            let confirmed = TranscriptLedger.join(ledger.committablePrefix.map(\.text))
                .split(whereSeparator: \.isWhitespace).count
            speech.update(ledger.text, confirmedWordCount: confirmed, now: ProcessInfo.processInfo.systemUptime)
            if !speech.text.isEmpty { try await appendRapidly(previous + " " + speech.text) }
            if lines.contains(where: { !$0.complete }) { partials += 1 }
            try checkClipboard()
        }
        ledger.update(finalLines)
        speech.update(ledger.text, final: true, now: ProcessInfo.processInfo.systemUptime)
        try await appendRapidly(previous + " " + speech.text)
        let (actual, _) = try snapshot()
        let insertion = " " + ledger.text
        let position = start + continued.utf16.count - baseline.utf16.count
        final = (continued as NSString).replacingCharacters(in: NSRange(location: position, length: 0), with: insertion)
        guard partials > 0, sameEditorText(actual, final) else { throw InsertionError.unavailable }
        print("Verified speech stream: \(partials) partial revisions, append-only input, and exact final transcript")
    } else { final = continued }
    final = try snapshot().0
    let previousSelection = try snapshot().1
    try await writer.setEditorSelection(NSRange(location: 0, length: 0), document: final, previous: previousSelection)
    do {
        try await writer.appendInEditor(" Unsafe revision")
        throw InsertionError.unavailable
    } catch InsertionError.focusChanged {}
    guard try snapshot().0.utf16.elementsEqual(final.utf16), try snapshot().1 == NSRange(location: 0, length: 0)
    else { throw InsertionError.unavailable }
    try checkClipboard()
    print("Live insertion checks: PASS (\(FocusTarget.isWebEditor(element) ? "keyboard input" : "Accessibility"), selection length \(selection.length))")
}
