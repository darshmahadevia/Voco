import AppKit
import ApplicationServices

@MainActor
struct FocusTarget {
    let processID: pid_t
    let element: AXUIElement?

    static func capture() -> FocusTarget? {
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier
        else { return nil }
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

    func validate() throws -> AXUIElement {
        guard AXIsProcessTrusted() else { throw InsertionError.permission }
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == processID,
              let element, let current = Self.focusedElement(in: processID), CFEqual(element, current)
        else { throw InsertionError.focusChanged }
        var subrole: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXSubroleAttribute as CFString, &subrole)
        if let subrole, CFEqual(subrole, kAXSecureTextFieldSubrole as CFString) { throw InsertionError.secureField }
        return element
    }

    func insert(_ text: String) async throws {
        guard AXIsProcessTrusted() else { throw InsertionError.permission }
        // Fn + Space can stop capture before the user has released the chord.
        for _ in 0..<20 {
            if !CGEventSource.flagsState(.combinedSessionState).contains(.maskSecondaryFn) { break }
            try await Task.sleep(for: .milliseconds(25))
        }
        let element = try validate()
        let modifiers: CGEventFlags = [.maskCommand, .maskAlternate, .maskControl, .maskShift, .maskSecondaryFn]
        guard CGEventSource.flagsState(.combinedSessionState).intersection(modifiers).isEmpty
        else { throw InsertionError.modifiers }
        let before = Self.textValue(of: element)
        var writable = DarwinBoolean(false)
        if AXUIElementIsAttributeSettable(element, kAXSelectedTextAttribute as CFString, &writable) == .success,
           writable.boolValue,
           AXUIElementSetAttributeValue(element, kAXSelectedTextAttribute as CFString, text as CFString) == .success {
            if let before {
                let after = Self.textValue(of: element)
                if let after, after != before { return }
                // Some apps acknowledge an AX write without changing their text.
            } else {
                // Without readable text, avoid a second insertion that could duplicate words.
                return
            }
        }
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == processID,
              let current = Self.focusedElement(in: processID), CFEqual(element, current)
        else { throw InsertionError.focusChanged }
        guard let source = CGEventSource(stateID: .privateState),
              let down = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false)
        else { throw InsertionError.unavailable }
        let pasteboard = NSPasteboard.general
        let savedItems = (pasteboard.pasteboardItems ?? []).map { item in
            item.types.compactMap { type in item.data(forType: type).map { (type, $0) } }
        }
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        let ourChange = pasteboard.changeCount
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
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
        // Let the destination consume the paste before restoring the clipboard.
        for _ in 0..<20 {
            try await Task.sleep(for: .milliseconds(25))
            if let before, let after = Self.textValue(of: element), after != before { return }
        }
        if let before, Self.textValue(of: element) == before { throw InsertionError.unavailable }
    }

    private static func textValue(of element: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &value) == .success
        else { return nil }
        return value as? String
    }
}

enum InsertionError: LocalizedError {
    case permission, focusChanged, secureField, modifiers, unavailable, liveUnsupported

    var errorDescription: String? {
        switch self {
        case .permission: "Allow Accessibility access to insert text, or copy it below."
        case .focusChanged: "The text field changed. Copy your words below and paste them where you want."
        case .secureField: "This is a password field. Copy your words if you want to keep them."
        case .modifiers: "Another shortcut key is held. Copy your words below."
        case .unavailable: "Text could not be inserted. Copy your words below."
        case .liveUnsupported: "This field supports insertion after release or a pause, rather than live correction."
        }
    }
}
