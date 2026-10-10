import AppKit
import ApplicationServices
import VocoCore

@MainActor
final class LiveTextWriter {
    private let target: FocusTarget
    private let element: AXUIElement
    private var buffer: LiveTextBuffer
    private var currentText = ""
    private var hasWritten = false
    private var normalizesEmptyPlaceholder = false
    private var editorDocument: String
    private var expectedDocument: String
    private let usesKeyboard: Bool

    init(target: FocusTarget) throws {
        self.target = target
        element = try target.validate()
        usesKeyboard = FocusTarget.isWebEditor(element)
        let attributes = usesKeyboard ? [kAXSelectedTextRangeAttribute] : [kAXSelectedTextAttribute, kAXSelectedTextRangeAttribute]
        for attribute in attributes {
            var writable = DarwinBoolean(false)
            guard AXUIElementIsAttributeSettable(element, attribute as CFString, &writable) == .success,
                  writable.boolValue else { throw InsertionError.liveUnsupported }
        }
        let snapshot = try Self.snapshot(element)
        editorDocument = snapshot.text
        expectedDocument = snapshot.text
        do { buffer = try LiveTextBuffer(document: snapshot.text, selection: snapshot.selection) }
        catch { throw InsertionError.liveUnsupported }
    }

    func appendInEditor(_ text: String) async throws {
        try Task.checkCancellation()
        guard currentText.isEmpty else { throw InsertionError.unavailable }
        try await updateInEditor(text)
        try commit()
    }

    func update(_ text: String) throws {
        guard !usesKeyboard else { throw InsertionError.liveUnsupported }
        _ = try target.validate()
        let snapshot = try Self.snapshot(element, failure: .unavailable)
        let plan: LiveTextPlan?
        do { plan = try buffer.plan(text: text, document: snapshot.text, selection: snapshot.selection) }
        catch { throw InsertionError.focusChanged }
        guard let plan else { return }
        do { try setSelection(plan.range) }
        catch {
            let actual = try Self.snapshot(element, failure: .unavailable)
            if !hasWritten, actual.text.utf16.elementsEqual(snapshot.text.utf16),
               actual.selection == snapshot.selection { throw InsertionError.liveUnsupported }
            throw InsertionError.unavailable
        }
        let selected = try Self.snapshot(element, failure: .unavailable)
        guard selected.text.utf16.elementsEqual(snapshot.text.utf16), selected.selection == plan.range
        else { throw InsertionError.unavailable }
        let result = AXUIElementSetAttributeValue(element, kAXSelectedTextAttribute as CFString, plan.replacement as CFString)
        let written = try Self.snapshot(element, failure: .unavailable)
        if !written.text.utf16.elementsEqual(plan.document.utf16) {
            if !hasWritten, written.text.utf16.elementsEqual(snapshot.text.utf16) {
                // Only an untouched first write can safely switch to buffered insertion.
                try setSelection(snapshot.selection)
                let restored = try Self.snapshot(element, failure: .unavailable)
                guard restored.text.utf16.elementsEqual(snapshot.text.utf16), restored.selection == snapshot.selection
                else { throw InsertionError.unavailable }
                throw InsertionError.liveUnsupported
            }
            throw InsertionError.unavailable
        }
        guard result == .success else { throw InsertionError.unavailable }
        // Text replacement does not consistently advance the caret across apps.
        try setSelection(plan.selection)
        let actual = try Self.snapshot(element, failure: .unavailable)
        do { try buffer.accept(plan, document: actual.text, selection: actual.selection) }
        catch { throw InsertionError.unavailable }
        currentText = text
        hasWritten = true
    }

    // Keyboard events reach the editor's input handlers without borrowing the clipboard.
    func updateInEditor(_ text: String) async throws {
        guard usesKeyboard else { try update(text); return }
        try Task.checkCancellation()
        _ = try target.validate()
        let modifiers: CGEventFlags = [.maskCommand, .maskAlternate, .maskControl, .maskShift]
        guard CGEventSource.flagsState(.combinedSessionState).intersection(modifiers).isEmpty
        else { throw InsertionError.modifiers }
        let before = try readSnapshot(failure: .unavailable)
        let plan: LiveTextPlan?
        do { plan = try buffer.plan(text: text, document: before.text, selection: before.selection) }
        catch { throw InsertionError.focusChanged }
        guard var plan else { return }
        do {
            if plan.range != before.selection {
                try await setEditorSelection(plan.range, document: before.text, previous: before.selection)
            }
        }
        catch {
            let actual = try readSnapshot(failure: .unavailable)
            if !hasWritten, actual.text.utf16.elementsEqual(before.text.utf16), actual.selection == before.selection {
                throw InsertionError.liveUnsupported
            }
            throw InsertionError.unavailable
        }
        // A successful AX call can be ignored. Never send a key to an unverified range.
        let selected = try readSnapshot(failure: .unavailable)
        guard selected.text.utf16.elementsEqual(before.text.utf16), selected.selection == plan.range
        else { throw InsertionError.unavailable }
        if Task.isCancelled {
            try await setEditorSelection(before.selection, document: before.text, previous: plan.range)
            throw CancellationError()
        }
        _ = try target.validate()
        var inserted = ""
        var insertionBaseline = before.text
        let mayConsumeEmptyPlaceholder = !hasWritten && before.text == "\n"
            && before.selection == NSRange(location: 0, length: 0) && plan.range == before.selection
        let chunks = Self.keyboardChunks(plan.replacement)
        for chunk in chunks {
            try Task.checkCancellation()
            _ = try target.validate()
            guard CGEventSource.flagsState(.combinedSessionState).intersection(modifiers).isEmpty
            else { throw InsertionError.modifiers }
            guard let source = CGEventSource(stateID: .privateState),
                  let down = CGEvent(keyboardEventSource: source, virtualKey: chunk.isEmpty ? 51 : 0, keyDown: true),
                  let up = CGEvent(keyboardEventSource: source, virtualKey: chunk.isEmpty ? 51 : 0, keyDown: false)
            else { throw InsertionError.unavailable }
            if !chunk.isEmpty {
                let units = Array(chunk.utf16)
                units.withUnsafeBufferPointer { units in
                    down.keyboardSetUnicodeString(stringLength: units.count, unicodeString: units.baseAddress)
                    up.keyboardSetUnicodeString(stringLength: units.count, unicodeString: units.baseAddress)
                }
            }
            down.setIntegerValueField(.eventSourceUserData, value: vocoInsertionEventMarker)
            up.setIntegerValueField(.eventSourceUserData, value: vocoInsertionEventMarker)
            let pendingBefore = try readSnapshot(failure: .unavailable, duringWrite: true)
            down.flags = []
            up.flags = []
            down.postToPid(target.processID)
            up.postToPid(target.processID)
            let previousInserted = inserted
            inserted += chunk
            let expected = (insertionBaseline as NSString).replacingCharacters(in: plan.range, with: inserted)
            let caret = NSRange(location: plan.range.location + inserted.utf16.count, length: 0)
            var pendingTexts = [pendingBefore.text, expected]
            var pendingSelections = [pendingBefore.selection, caret]
            var prefix = previousInserted
            pendingTexts.append((insertionBaseline as NSString).replacingCharacters(in: plan.range, with: prefix))
            pendingSelections.append(NSRange(location: plan.range.location + prefix.utf16.count, length: 0))
            for scalar in chunk.unicodeScalars {
                prefix += String(scalar)
                pendingTexts.append((insertionBaseline as NSString).replacingCharacters(in: plan.range, with: prefix))
                pendingSelections.append(NSRange(location: plan.range.location + prefix.utf16.count, length: 0))
            }
            if mayConsumeEmptyPlaceholder {
                pendingTexts += pendingTexts.map { $0.hasSuffix("\n") ? String($0.dropLast()) : $0 }
            }
            var consumed = false
            var stableReads = 0
            for _ in 0..<40 {
                // Drain the posted key before honoring cancellation, so selected text can be restored.
                await withCheckedContinuation { continuation in
                    DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(10)) { continuation.resume() }
                }
                _ = try target.validate()
                let actual = try readSnapshot(failure: .unavailable, duringWrite: true)
                // Empty rich-text paragraphs expose a synthetic newline until their first input.
                if mayConsumeEmptyPlaceholder, insertionBaseline == "\n",
                   matchesEditorText(actual.text, expected: inserted), actual.selection == caret {
                    insertionBaseline = ""
                    normalizesEmptyPlaceholder = true
                    buffer = try LiveTextBuffer(document: "", selection: before.selection)
                    guard let normalized = try buffer.plan(text: text, document: "", selection: before.selection)
                    else { throw InsertionError.unavailable }
                    plan = normalized
                }
                let settledText = (insertionBaseline as NSString).replacingCharacters(in: plan.range, with: inserted)
                if matchesEditorText(actual.text, expected: settledText), actual.selection == caret {
                    stableReads += 1
                    if stableReads == 2 { consumed = true; break }
                } else { stableReads = 0 }
                // AX publishes text and selection separately, and a Unicode batch can arrive in parts.
                // Only states belonging to this posted input may settle before another key is sent.
                guard pendingTexts.contains(where: { matchesEditorText(actual.text, expected: $0) }),
                      pendingSelections.contains(actual.selection)
                else { throw InsertionError.focusChanged }
            }
            if consumed, Task.isCancelled {
                if before.selection.length > 0 { try await setEditorSelection(before.selection, document: expected, previous: caret) }
                throw CancellationError()
            }
            // Posted keys may still arrive. A failed or partial write must never retry as paste.
            guard consumed else { throw InsertionError.unavailable }
        }
        _ = try target.validate()
        let written = try readSnapshot(failure: .unavailable, duringWrite: true)
        guard matchesEditorText(written.text, expected: plan.document),
              written.selection == NSRange(location: plan.range.location + inserted.utf16.count, length: 0)
        else { throw InsertionError.focusChanged }
        if plan.selection != written.selection {
            try await setEditorSelection(plan.selection, document: plan.document, previous: written.selection)
        }
        let restored = try readSnapshot(failure: .unavailable, duringWrite: true)
        guard matchesEditorText(restored.text, expected: plan.document) else { throw InsertionError.unavailable }
        do { try buffer.accept(plan, document: plan.document, selection: restored.selection) }
        catch { throw InsertionError.unavailable }
        editorDocument = restored.rawText
        expectedDocument = plan.document
        currentText = text
        hasWritten = true
    }

    func setEditorSelection(_ selection: NSRange, document: String, previous: NSRange) async throws {
        try setSelection(selection)
        var stableReads = 0
        for _ in 0..<40 {
            _ = try target.validate()
            let actual = try readSnapshot(failure: .unavailable, duringWrite: true)
            guard matchesEditorText(actual.text, expected: document) else { throw InsertionError.focusChanged }
            if actual.selection == selection {
                stableReads += 1
                if stableReads == 2 { return }
            } else {
                stableReads = 0
                guard actual.selection == previous else { throw InsertionError.focusChanged }
            }
            await withCheckedContinuation { continuation in
                DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(10)) { continuation.resume() }
            }
        }
        throw InsertionError.unavailable
    }

    private func matchesEditorText(_ actual: String, expected: String) -> Bool {
        guard usesKeyboard else { return actual.utf16.elementsEqual(expected.utf16) }
        guard actual.utf16.count == expected.utf16.count else { return false }
        return zip(actual.utf16, expected.utf16).allSatisfy { observed, intended in
            observed == intended || (observed == 0x00A0 && intended == 0x0020)
        }
    }

    private func readSnapshot(
        failure: InsertionError, duringWrite: Bool = false
    ) throws -> (text: String, selection: NSRange, rawText: String) {
        let snapshot = try Self.snapshot(element, failure: failure)
        if normalizesEmptyPlaceholder, snapshot.text == "\n", snapshot.selection == NSRange(location: 0, length: 0) {
            return ("", snapshot.selection, snapshot.text)
        }
        // Remember only the encoding observed after our verified write. Later user edits stay detectable.
        if usesKeyboard, !duringWrite {
            guard snapshot.text.utf16.elementsEqual(editorDocument.utf16) else { throw InsertionError.focusChanged }
            return (expectedDocument, snapshot.selection, snapshot.text)
        }
        return (snapshot.text, snapshot.selection, snapshot.text)
    }

    private static func keyboardChunks(_ text: String) -> [String] {
        guard !text.isEmpty else { return [""] }
        var chunks: [String] = []
        var chunk = ""
        // Use small input batches and keep surrogate pairs intact.
        for scalar in text.unicodeScalars {
            let next = String(scalar)
            if chunk.utf16.count + next.utf16.count > 20 {
                chunks.append(chunk)
                chunk = ""
            }
            chunk += next
        }
        if !chunk.isEmpty { chunks.append(chunk) }
        return chunks
    }

    func commit() throws {
        _ = try target.validate()
        let snapshot = try readSnapshot(failure: .unavailable)
        do { _ = try buffer.plan(text: currentText, document: snapshot.text, selection: snapshot.selection) }
        catch { throw InsertionError.focusChanged }
        try buffer.commit(document: snapshot.text, selection: snapshot.selection)
        currentText = ""
    }

    func setSelection(_ selection: NSRange) throws {
        var range = CFRange(location: selection.location, length: selection.length)
        guard let value = AXValueCreate(.cfRange, &range),
              AXUIElementSetAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, value) == .success
        else { throw InsertionError.unavailable }
    }

    static func snapshot(
        _ element: AXUIElement, failure: InsertionError = .liveUnsupported
    ) throws -> (text: String, selection: NSRange) {
        var value: CFTypeRef?, rangeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &value) == .success,
              let text = value as? String,
              AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &rangeValue) == .success,
              let rangeValue, CFGetTypeID(rangeValue) == AXValueGetTypeID()
        else { throw failure }
        var range = CFRange()
        guard AXValueGetValue(rangeValue as! AXValue, .cfRange, &range) else { throw failure }
        return (text, NSRange(location: range.location, length: range.length))
    }
}

@MainActor
final class BufferedTextWriter {
    private let target: FocusTarget
    private let element: AXUIElement
    private var buffer: LiveTextBuffer

    init(target: FocusTarget) throws {
        self.target = target
        element = try target.validate()
        let snapshot = try LiveTextWriter.snapshot(element, failure: .unavailable)
        buffer = try LiveTextBuffer(document: snapshot.text, selection: snapshot.selection)
    }

    func insert(_ text: String) async throws {
        try Task.checkCancellation()
        _ = try target.validate()
        let before = try LiveTextWriter.snapshot(element, failure: .unavailable)
        let plan: LiveTextPlan?
        do { plan = try buffer.plan(text: text, document: before.text, selection: before.selection) }
        catch { throw InsertionError.focusChanged }
        guard let plan else { return }
        func select(_ selection: NSRange) throws {
            var range = CFRange(location: selection.location, length: selection.length)
            guard let value = AXValueCreate(.cfRange, &range),
                  AXUIElementSetAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, value) == .success
            else { throw InsertionError.unavailable }
        }
        if plan.range != before.selection { try select(plan.range) }
        let selected = try LiveTextWriter.snapshot(element, failure: .unavailable)
        guard selected.text.utf16.elementsEqual(before.text.utf16), selected.selection == plan.range
        else { throw InsertionError.focusChanged }
        do { try await target.insert(plan.replacement) }
        catch {
            _ = try target.validate()
            let actual = try LiveTextWriter.snapshot(element, failure: .unavailable)
            if actual.text.utf16.elementsEqual(before.text.utf16), actual.selection == plan.range {
                try select(before.selection)
            }
            throw error
        }
        _ = try target.validate()
        let written = try LiveTextWriter.snapshot(element, failure: .unavailable)
        guard written.text.utf16.elementsEqual(plan.document.utf16) else { throw InsertionError.unavailable }
        try select(plan.selection)
        let restored = try LiveTextWriter.snapshot(element, failure: .unavailable)
        try buffer.accept(plan, document: restored.text, selection: restored.selection)
        try buffer.commit(document: restored.text, selection: restored.selection)
    }
}
