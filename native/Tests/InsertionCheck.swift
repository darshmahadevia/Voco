@MainActor enum InsertionFixture {
    static let pid = ProcessInfo.processInfo.processIdentifier + 1_000
    static let field = AXUIElementCreateApplication(pid + 1)
    static let webArea = AXUIElementCreateApplication(pid + 2)
    static let window = AXUIElementCreateApplication(pid + 3)
    static var web = false
    static var role = kAXTextAreaRole
    static var text = "Before. "
    static var selection = CFRange(location: 8, length: 0)
    static var rejectsWrite = false
    static var ignoresWrite = false
    static var partialWrite = false
    static var secure = false
    static var changedFocus = false
    static var flags: CGEventFlags = []
    static var syntheticFlags: CGEventFlags = []
    static var axWrites = 0
    static var pastes = 0
    static var trusted = true
    static var pasteWorks = true
    static var pasteLimit: Int?
    static var clipboardChanged = false
    static var keyboardEvents = 0
    static var onKeyboardEvent: (() -> Void)?
    static var normalizesSpaces = false
    static var usesEmptyParagraphPlaceholder = false

    static func reset(web: Bool = false) {
        self.web = web
        role = kAXTextAreaRole
        text = "Before. "
        selection = CFRange(location: 8, length: 0)
        rejectsWrite = false
        ignoresWrite = false
        partialWrite = false
        secure = false
        changedFocus = false
        flags = []
        syntheticFlags = []
        axWrites = 0
        pastes = 0
        trusted = true
        pasteWorks = true
        pasteLimit = nil
        clipboardChanged = false
        keyboardEvents = 0
        normalizesSpaces = false
        usesEmptyParagraphPlaceholder = false
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("Original clipboard", forType: .string)
    }

    static func replace(_ replacement: String) {
        if usesEmptyParagraphPlaceholder, text == "\n", selection.location == 0, selection.length == 0 { text = "" }
        text = (text as NSString).replacingCharacters(
            in: NSRange(location: selection.location, length: selection.length), with: replacement)
        if normalizesSpaces { text = text.replacingOccurrences(of: " ", with: "\u{00A0}") }
        selection = CFRange(location: selection.location + replacement.utf16.count, length: 0)
        if usesEmptyParagraphPlaceholder, text.isEmpty { text = "\n" }
    }
}

@MainActor enum NSWorkspace {
    static let shared = Workspace()
    struct Application { let processIdentifier: pid_t }
    @MainActor struct Workspace {
        var frontmostApplication: Application? { Application(processIdentifier: InsertionFixture.pid) }
        @discardableResult func open(_ url: URL) -> Bool { false }
        func activateFileViewerSelecting(_ urls: [URL]) {}
    }
}

func AXIsProcessTrusted() -> Bool { MainActor.assumeIsolated { InsertionFixture.trusted } }

@MainActor @discardableResult
func AXUIElementCopyAttributeValue(
    _ element: AXUIElement, _ attribute: CFString, _ value: UnsafeMutablePointer<CFTypeRef?>
) -> AXError {
    switch attribute as String {
    case kAXFocusedUIElementAttribute:
        value.pointee = InsertionFixture.changedFocus ? InsertionFixture.window : InsertionFixture.field
    case kAXRoleAttribute:
        value.pointee = (CFEqual(element, InsertionFixture.webArea) ? "AXWebArea" : InsertionFixture.role) as CFString
    case kAXParentAttribute:
        guard InsertionFixture.web, CFEqual(element, InsertionFixture.field) else { return .noValue }
        value.pointee = InsertionFixture.webArea
    case kAXSubroleAttribute:
        value.pointee = (InsertionFixture.secure ? kAXSecureTextFieldSubrole : "AXStandard") as CFString
    case kAXValueAttribute:
        value.pointee = InsertionFixture.text as CFString
    case kAXSelectedTextRangeAttribute:
        var range = InsertionFixture.selection
        value.pointee = AXValueCreate(.cfRange, &range)
    default: return .attributeUnsupported
    }
    return .success
}

@MainActor func AXUIElementIsAttributeSettable(
    _ element: AXUIElement, _ attribute: CFString, _ settable: UnsafeMutablePointer<DarwinBoolean>
) -> AXError {
    settable.pointee = true
    return .success
}

@MainActor @discardableResult
func AXUIElementSetAttributeValue(_ element: AXUIElement, _ attribute: CFString, _ value: CFTypeRef) -> AXError {
    switch attribute as String {
    case "AXManualAccessibility": break
    case kAXSelectedTextAttribute:
        InsertionFixture.axWrites += 1
        if InsertionFixture.rejectsWrite { return .notImplemented }
        if InsertionFixture.ignoresWrite { return .success }
        InsertionFixture.replace(InsertionFixture.partialWrite ? "Wrong" : value as! String)
    default: return .attributeUnsupported
    }
    return .success
}

@MainActor final class CGEventSource {
    init?(stateID: CGEventSourceStateID) {}
    static func flagsState(_ state: CGEventSourceStateID) -> CGEventFlags {
        state == .hidSystemState ? InsertionFixture.flags : InsertionFixture.flags.union(InsertionFixture.syntheticFlags)
    }
}

@MainActor final class CGEvent {
    let down: Bool
    let key: CGKeyCode
    var flags: CGEventFlags = []
    init?(keyboardEventSource: CGEventSource, virtualKey: CGKeyCode, keyDown: Bool) { down = keyDown; key = virtualKey }
    func setIntegerValueField(_ field: CGEventField, value: Int64) {}
    func post(tap: CGEventTapLocation) {
        InsertionFixture.syntheticFlags = flags
        guard down else { return }
        guard key == 9 else { InsertionFixture.keyboardEvents += 1; return }
        InsertionFixture.pastes += 1
        if InsertionFixture.pasteWorks, let text = NSPasteboard.general.string(forType: .string) {
            InsertionFixture.replace(InsertionFixture.pasteLimit.map { String(text.prefix($0)) } ?? text)
        }
        if InsertionFixture.clipboardChanged {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString("New clipboard", forType: .string)
        }
    }
}

@MainActor final class NSPasteboard {
    static let general = NSPasteboard()
    private let storage = AppKit.NSPasteboard(name: .init("Voco-test-\(UUID().uuidString)"))
    var pasteboardItems: [NSPasteboardItem]? { storage.pasteboardItems }
    var changeCount: Int { storage.changeCount }
    @discardableResult func clearContents() -> Int { storage.clearContents() }
    @discardableResult func setString(_ text: String, forType type: AppKit.NSPasteboard.PasteboardType) -> Bool {
        storage.setString(text, forType: type)
    }
    func string(forType type: AppKit.NSPasteboard.PasteboardType) -> String? { storage.string(forType: type) }
    @discardableResult func writeObjects(_ objects: [NSPasteboardItem]) -> Bool { storage.writeObjects(objects) }
}

@main struct InsertionCheck {
    @MainActor static func main() async throws {
        setbuf(stdout, nil)
        func target() throws -> FocusTarget {
            guard let target = FocusTarget.capture() else { throw InsertionError.focusUnavailable }
            return target
        }
        InsertionFixture.reset()
        InsertionFixture.role = "AXButton"
        do {
            try await target().insert("Hello.")
            preconditionFailure("A non-text control must reject dictation")
        } catch InsertionError.unavailable {}
        precondition(InsertionFixture.text == "Before. " && InsertionFixture.axWrites == 0 && InsertionFixture.pastes == 0)
        print("Non-text controls: rejected without writes")
        InsertionFixture.reset(web: true)
        try await target().insert("Hello. 🍦")
        precondition(InsertionFixture.text == "Before. Hello. 🍦")
        precondition(InsertionFixture.axWrites == 0 && InsertionFixture.pastes == 1)
        precondition(NSPasteboard.general.string(forType: .string) == "Original clipboard")
        print("Web editor: exact paste, once, clipboard restored")
        try await target().insert(" Next phrase.")
        precondition(InsertionFixture.text == "Before. Hello. 🍦 Next phrase." && InsertionFixture.pastes == 2)
        precondition(InsertionFixture.syntheticFlags.intersection(.maskCommand).isEmpty)
        print("Consecutive buffered phrases: paste releases its synthetic Command modifier")

        InsertionFixture.reset(web: true)
        InsertionFixture.pasteLimit = 4
        do {
            try await target().insert("Keep the whole transcript.")
            preconditionFailure("A truncated paste must report failure rather than discard the transcript")
        } catch InsertionError.unavailable {}
        precondition(InsertionFixture.text == "Before. Keep" && InsertionFixture.pastes == 1)
        precondition(NSPasteboard.general.string(forType: .string) == "Original clipboard")
        print("Truncated buffered paste: reported failure, one paste, clipboard restored")

        InsertionFixture.reset(web: true)
        InsertionFixture.normalizesSpaces = true
        try await target().insert("Hello world. 🍦")
        precondition(InsertionFixture.text == "Before.\u{00A0}Hello\u{00A0}world.\u{00A0}🍦" && InsertionFixture.pastes == 1)
        InsertionFixture.reset(web: true)
        InsertionFixture.normalizesSpaces = true
        InsertionFixture.usesEmptyParagraphPlaceholder = true
        InsertionFixture.text = "\n"
        InsertionFixture.selection = CFRange(location: 0, length: 0)
        try await target().insert("Hello world. 🍦")
        precondition(InsertionFixture.text == "Hello\u{00A0}world.\u{00A0}🍦" && InsertionFixture.pastes == 1)
        print("Buffered rich-text paste: space normalization and empty paragraph placeholder accepted")

        for web in [false, true] {
            InsertionFixture.reset(web: web)
            InsertionFixture.text = "Before selected after"
            InsertionFixture.selection = CFRange(location: 0, length: 0)
            let finalTarget = try target()
            InsertionFixture.selection = CFRange(location: 7, length: 8)
            try await finalTarget.insert("Final words. 🧑🏽‍💻")
            precondition(InsertionFixture.text == "Before Final words. 🧑🏽‍💻 after")
            precondition(InsertionFixture.selection.location == 7 + "Final words. 🧑🏽‍💻".utf16.count)
            precondition(InsertionFixture.selection.length == 0)
            precondition(InsertionFixture.pastes == (web ? 1 : 0))
            precondition(InsertionFixture.axWrites == (web ? 0 : 1))
            precondition(InsertionFixture.keyboardEvents == 0)
            precondition(NSPasteboard.general.string(forType: .string) == "Original clipboard")
        }
        print("Final transcript: one insertion at the current selection, Unicode, clipboard restored")
        for rejects in [true, false] {
            InsertionFixture.reset()
            InsertionFixture.rejectsWrite = rejects
            InsertionFixture.ignoresWrite = !rejects
            try await target().insert("Hello.")
            precondition(InsertionFixture.text == "Before. Hello." && InsertionFixture.pastes == 1)
        }
        print("Rejected and ignored AX writes: one buffered paste")

        InsertionFixture.reset()
        InsertionFixture.partialWrite = true
        do {
            try await target().insert("Hello.")
            preconditionFailure("A partial AX write must not be retried as paste")
        } catch InsertionError.unavailable {}
        precondition(InsertionFixture.text == "Before. Wrong" && InsertionFixture.pastes == 0)
        print("Partial AX write: failure without duplicate paste")

        InsertionFixture.reset(web: true)
        InsertionFixture.selection = CFRange(location: 0, length: 7)
        try await target().insert("After.")
        precondition(InsertionFixture.text == "After. ")
        InsertionFixture.reset(web: true)
        InsertionFixture.selection = CFRange(location: 0, length: 7)
        try await target().insert("Before.")
        precondition(InsertionFixture.text == "Before. " && InsertionFixture.pastes == 1)
        print("Selected text replacement, including identical text: pasted exactly once")

        InsertionFixture.reset(web: true)
        InsertionFixture.clipboardChanged = true
        try await target().insert("Hello.")
        precondition(NSPasteboard.general.string(forType: .string) == "New clipboard")
        InsertionFixture.reset(web: true)
        InsertionFixture.pasteWorks = false
        do {
            try await target().insert("Hello.")
            preconditionFailure("Failed paste must report recovery")
        } catch InsertionError.unavailable {}
        precondition(InsertionFixture.pastes == 1 && NSPasteboard.general.string(forType: .string) == "Original clipboard")
        print("Failed paste detected; clipboard ownership respected")

        for failure in [InsertionError.secureField, .focusChanged, .permission, .modifiers] {
            InsertionFixture.reset(web: true)
            let captured = try target()
            switch failure {
            case .secureField: InsertionFixture.secure = true
            case .focusChanged: InsertionFixture.changedFocus = true
            case .permission: InsertionFixture.trusted = false
            case .modifiers: InsertionFixture.flags = .maskCommand
            default: break
            }
            do {
                try await captured.insert("Hello.")
                preconditionFailure("Unsafe insertion must stop")
            } catch let error as InsertionError {
                precondition(error == failure)
            }
            precondition(InsertionFixture.pastes == 0 && InsertionFixture.axWrites == 0)
        }
        print("Password, focus, permission, and modifier guards: no writes")
        print("Insertion checks: PASS")
    }
}
