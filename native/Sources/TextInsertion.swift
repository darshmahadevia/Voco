import AppKit
import ApplicationServices

let vocoInsertionEventMarker: Int64 = 0x564F434F

@MainActor
struct FocusTarget {
    let processID: pid_t
    let element: AXUIElement?

    static func capture() -> FocusTarget? {
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier
        else { return nil }
        let application = AXUIElementCreateApplication(app.processIdentifier)
        _ = AXUIElementSetAttributeValue(application, "AXManualAccessibility" as CFString, kCFBooleanTrue)
        return FocusTarget(processID: app.processIdentifier, element: focusedElement(in: app.processIdentifier))
    }

    private static func focusedElement(in pid: pid_t) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            AXUIElementCreateApplication(pid), kAXFocusedUIElementAttribute as CFString, &value
        ) == .success, let value, CFGetTypeID(value) == AXUIElementGetTypeID()
        else { return nil }
        return (value as! AXUIElement)
    }

    func resolved() async throws -> FocusTarget {
        guard element == nil else { return self }
        guard AXIsProcessTrusted() else { throw InsertionError.permission }
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == processID
        else { throw InsertionError.focusChanged }
        guard let element = try await Self.waitForFocusedElement(in: processID)
        else { throw InsertionError.focusUnavailable }
        let resolved = FocusTarget(processID: processID, element: element)
        _ = try resolved.validate()
        return resolved
    }

    private static func waitForFocusedElement(in pid: pid_t) async throws -> AXUIElement? {
        for _ in 0..<12 {
            try Task.checkCancellation()
            guard AXIsProcessTrusted() else { throw InsertionError.permission }
            guard NSWorkspace.shared.frontmostApplication?.processIdentifier == pid
            else { throw InsertionError.focusChanged }
            if let element = focusedElement(in: pid) { return element }
            try await Task.sleep(for: .milliseconds(25))
        }
        return nil
    }

    func validate() throws -> AXUIElement {
        guard AXIsProcessTrusted() else { throw InsertionError.permission }
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == processID, let element
        else { throw InsertionError.focusChanged }
        guard let current = Self.focusedElement(in: processID)
        else { throw InsertionError.focusUnavailable }
        guard CFEqual(element, current)
        else { throw InsertionError.focusChanged }
        var subrole: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXSubroleAttribute as CFString, &subrole)
        if let subrole, CFEqual(subrole, kAXSecureTextFieldSubrole as CFString) { throw InsertionError.secureField }
        var role: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &role) == .success,
              let role, ["AXTextField", "AXTextArea", "AXComboBox"].contains(where: { CFEqual(role, $0 as CFString) })
        else { throw InsertionError.unavailable }
        return element
    }

    static func isWebEditor(_ element: AXUIElement) -> Bool {
        var current = element
        for _ in 0..<64 {
            var role: CFTypeRef?
            if AXUIElementCopyAttributeValue(current, kAXRoleAttribute as CFString, &role) == .success,
               let role, CFEqual(role, "AXWebArea" as CFString) { return true }
            var parent: CFTypeRef?
            guard AXUIElementCopyAttributeValue(current, kAXParentAttribute as CFString, &parent) == .success,
                  let parent, CFGetTypeID(parent) == AXUIElementGetTypeID(), !CFEqual(current, parent)
            else { return false }
            current = parent as! AXUIElement
        }
        return false
    }

    func insert(_ text: String) async throws {
        guard !text.isEmpty else { return }
        try Task.checkCancellation()
        guard AXIsProcessTrusted() else { throw InsertionError.permission }
        let modifiers: CGEventFlags = [.maskCommand, .maskAlternate, .maskControl, .maskShift, .maskSecondaryFn]
        for _ in 0..<20 {
            if CGEventSource.flagsState(.combinedSessionState).intersection(modifiers).isEmpty { break }
            try await Task.sleep(for: .milliseconds(25))
        }
        try Task.checkCancellation()
        let element = try validate()
        guard CGEventSource.flagsState(.combinedSessionState).intersection(modifiers).isEmpty
        else { throw InsertionError.modifiers }
        let before = Self.textValue(of: element)
        let selectionBefore = Self.selectedRange(of: element)
        let isWebEditor = Self.isWebEditor(element)
        let expected: String? = before.flatMap { value in
            selectionBefore.flatMap { selection in
                guard selection.location >= 0, selection.length >= 0,
                      selection.location <= value.utf16.count,
                      selection.length <= value.utf16.count - selection.location else { return nil }
                return (value as NSString).replacingCharacters(
                    in: NSRange(location: selection.location, length: selection.length), with: text)
            }
        }
        var writable = DarwinBoolean(false)
        // Web editors need input/paste events to update their application state.
        if !isWebEditor,
           AXUIElementIsAttributeSettable(element, kAXSelectedTextAttribute as CFString, &writable) == .success,
           writable.boolValue,
           AXUIElementSetAttributeValue(element, kAXSelectedTextAttribute as CFString, text as CFString) == .success {
            if let before {
                let after = Self.textValue(of: element)
                if let expected, let after, after != before, !after.utf16.elementsEqual(expected.utf16) {
                    // An app can accept an AX write but insert only part of it. Do not retry and duplicate it.
                    throw InsertionError.unavailable
                }
                if let after, after != before || Self.didReplaceIdenticalText(
                    text, before: before, after: after, selection: selectionBefore, element: element
                ) { return }
                // Some apps acknowledge an AX write without changing their text.
            } else {
                // Without readable text, avoid a second insertion that could duplicate words.
                return
            }
        }
        try Task.checkCancellation()
        _ = try validate()
        guard let source = CGEventSource(stateID: .privateState),
              let down = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false)
        else { throw InsertionError.unavailable }
        let pasteboard = NSPasteboard.general
        let savedItems = (pasteboard.pasteboardItems ?? []).map { item in
            item.types.compactMap { type in item.data(forType: type).map { (type, $0) } }
        }
        pasteboard.clearContents()
        var ourChange = pasteboard.changeCount
        defer {
            if pasteboard.changeCount == ourChange {
                pasteboard.clearContents()
                let items = savedItems.map { representations in
                    let item = NSPasteboardItem()
                    for (type, data) in representations { item.setData(data, forType: type) }
                    return item
                }
                pasteboard.writeObjects(items)
            }
        }
        guard pasteboard.setString(text, forType: .string) else { throw InsertionError.unavailable }
        ourChange = pasteboard.changeCount
        try Task.checkCancellation()
        _ = try validate()
        down.setIntegerValueField(.eventSourceUserData, value: vocoInsertionEventMarker)
        up.setIntegerValueField(.eventSourceUserData, value: vocoInsertionEventMarker)
        down.flags = .maskCommand
        // Release the synthetic chord so the next phrase does not see Command held.
        up.flags = []
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
        // Let the destination consume the paste before restoring the clipboard.
        for _ in 0..<40 {
            try await Task.sleep(for: .milliseconds(25))
            if let before, let after = Self.textValue(of: element) {
                if let expected {
                    let replacedEmptyParagraph = isWebEditor && before == "\n"
                        && selectionBefore?.location == 0 && selectionBefore?.length == 0
                    let matches = Self.matchesPastedText(after, expected: expected, web: isWebEditor)
                        || (replacedEmptyParagraph && Self.matchesPastedText(after, expected: text, web: true))
                    if matches && (after != before || Self.didReplaceIdenticalText(
                        text, before: before, after: after, selection: selectionBefore, element: element
                    )) { return }
                } else if after != before || Self.didReplaceIdenticalText(
                    text, before: before, after: after, selection: selectionBefore, element: element
                ) { return }
            }
        }
        // A posted paste must never be retried when a field accepts only a prefix.
        if expected != nil { throw InsertionError.unavailable }
        if let before, Self.textValue(of: element) == before { throw InsertionError.unavailable }
    }

    private static func matchesPastedText(_ actual: String, expected: String, web: Bool) -> Bool {
        guard web else { return actual.utf16.elementsEqual(expected.utf16) }
        guard actual.utf16.count == expected.utf16.count else { return false }
        return zip(actual.utf16, expected.utf16).allSatisfy { observed, intended in
            observed == intended || (observed == 0x00A0 && intended == 0x0020)
        }
    }

    private static func textValue(of element: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &value) == .success
        else { return nil }
        return value as? String
    }

    private static func selectedRange(of element: AXUIElement) -> CFRange? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var range = CFRange()
        guard AXValueGetValue(value as! AXValue, .cfRange, &range) else { return nil }
        return range
    }

    private static func didReplaceIdenticalText(
        _ text: String, before: String, after: String, selection: CFRange?, element: AXUIElement
    ) -> Bool {
        guard before.utf16.elementsEqual(after.utf16), let selection, selection.location >= 0,
              selection.length > 0, selection.location <= before.utf16.count,
              selection.length <= before.utf16.count - selection.location,
              (before as NSString).substring(with: NSRange(location: selection.location, length: selection.length))
                  .utf16.elementsEqual(text.utf16),
              let current = selectedRange(of: element) else { return false }
        return current.location == selection.location + text.utf16.count && current.length == 0
    }
}

enum InsertionError: LocalizedError {
    case permission, focusChanged, focusUnavailable, secureField, modifiers, unavailable

    var errorDescription: String? {
        switch self {
        case .permission: "Allow Accessibility access to insert text, or copy it below."
        case .focusChanged: "The text field changed. Copy your words below and paste them where you want."
        case .focusUnavailable: "Voco could not read the focused text field. Click inside it and try again, or copy your words below."
        case .secureField: "This is a password field. Copy your words if you want to keep them."
        case .modifiers: "Another shortcut key is held. Copy your words below."
        case .unavailable: "Text could not be inserted. Copy your words below."
        }
    }
}
