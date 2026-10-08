import AppKit
import ApplicationServices

@MainActor
func verifyInsertion(audioFixture: URL? = nil) async throws {
    guard AXIsProcessTrusted() else { throw InsertionError.permission }
    let file = FileManager.default.temporaryDirectory.appendingPathComponent("Voco-insertion-test-\(UUID().uuidString).txt")
    try "Disposable Voco test.\n".write(to: file, atomically: true, encoding: .utf8)
    guard let textEdit = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.TextEdit")
    else { throw InsertionError.unavailable }
    let configuration = NSWorkspace.OpenConfiguration()
    configuration.activates = true
    let app = try await NSWorkspace.shared.open([file], withApplicationAt: textEdit, configuration: configuration)
    try await Task.sleep(for: .milliseconds(500))
    guard let target = FocusTarget.capture(), target.processID == app.processIdentifier,
          let element = target.element else { throw InsertionError.focusChanged }
    func value() throws -> String {
        var result: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &result) == .success,
              let text = result as? String else { throw InsertionError.unavailable }
        return text
    }
    guard try value() == "Disposable Voco test.\n" else { throw InsertionError.focusChanged }
    for index in 1...5 {
        let before = try value()
        var range = CFRange(location: before.utf16.count, length: 0)
        guard let selection = AXValueCreate(.cfRange, &range),
              AXUIElementSetAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, selection) == .success
        else { throw InsertionError.unavailable }
        let words = " Test \(index)."
        try await target.insert(words)
        guard try value() == before + words else { throw InsertionError.unavailable }
        print("Insertion \(index): exact text verified")
    }
    let baseline = try value()
    var atEnd = CFRange(location: baseline.utf16.count, length: 0)
    guard let endSelection = AXValueCreate(.cfRange, &atEnd),
          AXUIElementSetAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, endSelection) == .success
    else { throw InsertionError.unavailable }
    let writer = try LiveTextWriter(target: target)
    for words in [" I scream", " Ice cream.", " Ice cream. 🍦"] {
        let start = ContinuousClock.now
        try writer.update(words)
        guard try value() == baseline + words else { throw InsertionError.unavailable }
        print("Live correction verified in \(start.duration(to: .now))")
    }
    try writer.commit()
    try writer.update(" Next sentence.")
    let expected = baseline + " Ice cream. 🍦 Next sentence."
    guard try value() == expected else { throw InsertionError.unavailable }
    var moved = CFRange(location: 0, length: 0)
    guard let movedSelection = AXValueCreate(.cfRange, &moved),
          AXUIElementSetAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, movedSelection) == .success
    else { throw InsertionError.unavailable }
    do {
        try writer.update(" Changed sentence.")
        throw InsertionError.unavailable
    } catch InsertionError.focusChanged {
        guard try value() == expected else { throw InsertionError.unavailable }
        print("Caret movement rejected without changing the document")
    }
    print("Live typing, corrections, and pause continuation verified")
    if let audioFixture {
        var end = CFRange(location: expected.utf16.count, length: 0)
        guard let selection = AXValueCreate(.cfRange, &end),
              AXUIElementSetAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, selection) == .success
        else { throw InsertionError.unavailable }
        let speechWriter = try LiveTextWriter(target: target)
        var writeError: Error?
        var previewWrites = 0
        let text = try await SpeechSession.transcribeStream(audioFixture) { transcript in
            guard writeError == nil, !transcript.text.isEmpty else { return }
            do {
                try speechWriter.update(" " + transcript.text)
                if transcript.hasProvisionalText { previewWrites += 1 }
            } catch { writeError = error }
        }
        if let writeError { throw writeError }
        try speechWriter.update(" " + text)
        guard previewWrites > 0, try value() == expected + " " + text else { throw InsertionError.unavailable }
        print("Live speech: \(previewWrites) provisional updates and exact final text verified")
    }
    print("Disposable document: \(file.path)")
}
