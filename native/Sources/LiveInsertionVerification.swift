import AppKit
import ApplicationServices
import Foundation

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
    for words in ["Hello", "Hello world.", "Hello there.", "", "Goodbye"] {
        try await writer.updateInEditor(words)
        let actual = try LiveTextWriter.snapshot(element)
        guard actual.text == words || (words.isEmpty && actual.text == "\n"),
              actual.selection == NSRange(location: words.utf16.count, length: 0),
              NSPasteboard.general.changeCount == clipboardCount
        else { throw InsertionError.unavailable }
        print("Verified empty rich editor revision: \(words.debugDescription)")
    }
    try writer.commit()
    try await writer.updateInEditor(" again.")
    guard try LiveTextWriter.snapshot(element).text == "Goodbye again." else { throw InsertionError.unavailable }
    try writer.commit()
    let document = try LiveTextWriter.snapshot(element).text
    try await writer.setEditorSelection(NSRange(location: 0, length: 0), document: document,
                                        previous: NSRange(location: document.utf16.count, length: 0))
    do {
        try await writer.updateInEditor("Unsafe")
        throw InsertionError.unavailable
    } catch InsertionError.focusChanged {}
    guard try LiveTextWriter.snapshot(element).text == document,
          NSPasteboard.general.changeCount == clipboardCount else { throw InsertionError.unavailable }
    print("Empty rich editor checks: PASS")
}

@MainActor
func verifyLiveInsertion(expected: String, audioFixture: URL? = nil, engine: MoonshineEngine? = nil) async throws {
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
    var final = ""
    for words in [" I scream", " Ice cream. 🍦", " Ice cream. 🍦 and coffee.", " Ice cream. 🍦", "", " " + String(repeating: "Long 🍦 phrase. ", count: 8)] {
        try await writer.updateInEditor(words)
        let (actual, caret) = try snapshot()
        let document = (baseline as NSString).replacingCharacters(in: NSRange(location: start, length: 0), with: words)
        guard sameEditorText(actual, document),
              caret == (selection.length > 0 ? selection : NSRange(location: start + words.utf16.count, length: 0))
        else { throw InsertionError.unavailable }
        try checkClipboard()
        final = document
        print("Verified live revision: \(words.debugDescription)")
    }
    try writer.commit()
    try await writer.updateInEditor(" Next phrase.")
    let continued = (final as NSString).replacingCharacters(in: NSRange(location: start + final.utf16.count - baseline.utf16.count, length: 0), with: " Next phrase.")
    guard sameEditorText(try snapshot().0, continued) else { throw InsertionError.unavailable }
    try checkClipboard()
    if let audioFixture, let engine {
        try writer.commit()
        var partials = 0
        var ledger = TranscriptLedger()
        var lastText = ""
        let finalLines = try await transcribeStreamingFile(audioFixture, engine: engine) { lines in
            ledger.update(lines)
            guard !ledger.text.isEmpty, ledger.text != lastText else { return }
            try await writer.updateInEditor(" " + ledger.text)
            if lines.contains(where: { !$0.complete }) { partials += 1 }
            lastText = ledger.text
            try checkClipboard()
        }
        ledger.update(finalLines)
        try await writer.updateInEditor(" " + ledger.text)
        let (actual, _) = try snapshot()
        let insertion = " " + ledger.text
        let position = start + continued.utf16.count - baseline.utf16.count
        final = (continued as NSString).replacingCharacters(in: NSRange(location: position, length: 0), with: insertion)
        guard partials > 0, sameEditorText(actual, final) else { throw InsertionError.unavailable }
        print("Verified Moonshine stream: \(partials) partial revisions and exact final transcript")
    } else { final = continued }
    final = try snapshot().0
    let previousSelection = try snapshot().1
    try await writer.setEditorSelection(NSRange(location: 0, length: 0), document: final, previous: previousSelection)
    do {
        try await writer.updateInEditor(" Unsafe revision")
        throw InsertionError.unavailable
    } catch InsertionError.focusChanged {}
    guard try snapshot().0.utf16.elementsEqual(final.utf16), try snapshot().1 == NSRange(location: 0, length: 0)
    else { throw InsertionError.unavailable }
    try checkClipboard()
    print("Live insertion checks: PASS (\(FocusTarget.isWebEditor(element) ? "keyboard input" : "Accessibility"), selection length \(selection.length))")
}
