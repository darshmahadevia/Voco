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
    static var unreadableAfterWrite = false
    static var rejectsSelection = false
    static var keyboardEvents = 0
    static var onKeyboardEvent: (() -> Void)?
    static var keyboardPublicationDelay = 0
    static var publishesCaretFirst = false
    static var publishesPartialInput = false
    static var publishesDeletionFirst = false
    static var pendingPublicationReads = 0
    static var previousText = ""
    static var previousSelection = CFRange()
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
        unreadableAfterWrite = false
        rejectsSelection = false
        keyboardEvents = 0
        onKeyboardEvent = nil
        keyboardPublicationDelay = 0
        publishesCaretFirst = false
        publishesPartialInput = false
        publishesDeletionFirst = false
        pendingPublicationReads = 0
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
        if InsertionFixture.unreadableAfterWrite && InsertionFixture.axWrites > 0 { return .noValue }
        value.pointee = (InsertionFixture.pendingPublicationReads > 0 && InsertionFixture.publishesCaretFirst
            ? InsertionFixture.previousText : InsertionFixture.text) as CFString
    case kAXSelectedTextRangeAttribute:
        var range = InsertionFixture.pendingPublicationReads > 0
            && (!InsertionFixture.publishesCaretFirst || InsertionFixture.publishesPartialInput)
            ? InsertionFixture.previousSelection : InsertionFixture.selection
        value.pointee = AXValueCreate(.cfRange, &range)
        if InsertionFixture.pendingPublicationReads > 0 { InsertionFixture.pendingPublicationReads -= 1 }
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
    case kAXSelectedTextRangeAttribute:
        if InsertionFixture.rejectsSelection { return .notImplemented }
        _ = AXValueGetValue(value as! AXValue, .cfRange, &InsertionFixture.selection)
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
    var unicode: String?
    var flags: CGEventFlags = []
    init?(keyboardEventSource: CGEventSource, virtualKey: CGKeyCode, keyDown: Bool) { down = keyDown; key = virtualKey }
    func keyboardSetUnicodeString(stringLength: Int, unicodeString: UnsafePointer<UniChar>?) {
        if let unicodeString { unicode = String(decoding: UnsafeBufferPointer(start: unicodeString, count: stringLength), as: UTF16.self) }
    }
    func setIntegerValueField(_ field: CGEventField, value: Int64) {}
    func postToPid(_ pid: pid_t) { post(tap: .cghidEventTap) }
    func post(tap: CGEventTapLocation) {
        InsertionFixture.syntheticFlags = flags
        guard down else { return }
        if let unicode = unicode ?? (key == 51 ? "" : nil) {
            InsertionFixture.keyboardEvents += 1
            InsertionFixture.previousText = InsertionFixture.text
            InsertionFixture.previousSelection = InsertionFixture.selection
            if InsertionFixture.publishesPartialInput {
                let firstScalar = String(unicode.unicodeScalars.prefix(InsertionFixture.publishesDeletionFirst ? 0 : 1))
                InsertionFixture.previousText = (InsertionFixture.text as NSString).replacingCharacters(
                    in: NSRange(location: InsertionFixture.selection.location, length: InsertionFixture.selection.length),
                    with: firstScalar)
                InsertionFixture.previousSelection = CFRange(location: InsertionFixture.selection.location + firstScalar.utf16.count,
                                                             length: 0)
            }
            InsertionFixture.replace(unicode)
            InsertionFixture.pendingPublicationReads = InsertionFixture.keyboardPublicationDelay
            InsertionFixture.onKeyboardEvent?()
            return
        }
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
        for web in [false, true] {
            for selected in [false, true] {
                InsertionFixture.reset(web: web)
                InsertionFixture.text = "Before selected after"
                let selection = CFRange(location: selected ? 7 : 15, length: selected ? 8 : 0)
                InsertionFixture.selection = selection
                let writer = try LiveTextWriter(target: target())
                var stream = StableText()
                var inserted = ""
                for (text, time, final) in [(" I scream is good", 0.0, false),
                                           (" Ice cream is good", 0.24, false),
                                           (" Ice cream is good", 0.48, false),
                                           (" Cold cream is lovely. 🧑🏽‍💻", 0.6, true)] {
                    stream.update(text, final: final, now: time)
                    while inserted != stream.text {
                        let chunk = LiveTextDelivery.nextChunk(in: String(stream.text.dropFirst(inserted.count)))
                        let before = InsertionFixture.text
                        try await writer.appendInEditor(chunk)
                        inserted += chunk
                        precondition(InsertionFixture.text == "Before selected" + inserted + " after")
                        precondition(InsertionFixture.text.utf16.count > before.utf16.count)
                    }
                }
                precondition(inserted == "Ice cream is lovely. 🧑🏽‍💻")
                precondition(InsertionFixture.pastes == 0)
                precondition(NSPasteboard.general.string(forType: .string) == "Original clipboard")
                if selected {
                    precondition(InsertionFixture.selection.location == selection.location
                                 && InsertionFixture.selection.length == selection.length)
                }
                InsertionFixture.selection = CFRange(location: 0, length: 0)
                do {
                    try await writer.appendInEditor(" Unsafe")
                    preconditionFailure("Append-only input must reject a moved caret")
                } catch InsertionError.focusChanged {}
            }
        }
        print("Rapid append-only dictation: stable corrections, whole graphemes, selections, clipboard, and caret refusal")
        InsertionFixture.reset(web: true)
        InsertionFixture.text = "Before selected after"
        InsertionFixture.selection = CFRange(location: 7, length: 8)
        let canceledAppendWriter = try LiveTextWriter(target: target())
        var appendTask: Task<Void, Error>?
        InsertionFixture.onKeyboardEvent = { appendTask?.cancel() }
        appendTask = Task {
            try await canceledAppendWriter.appendInEditor("A")
            try await canceledAppendWriter.appendInEditor("B")
        }
        do {
            try await appendTask?.value
            preconditionFailure("Canceled rapid insertion must stop after the posted character")
        } catch is CancellationError {}
        precondition(InsertionFixture.text == "Before selectedA after" && InsertionFixture.keyboardEvents == 1)
        precondition(InsertionFixture.selection.location == 7 && InsertionFixture.selection.length == 8)
        print("Canceled rapid insertion: one posted character settles, selection survives, remaining text stays unwritten")
        InsertionFixture.reset()
        InsertionFixture.role = "AXButton"
        do {
            try await target().insert("Hello.")
            preconditionFailure("A non-text control must reject dictation")
        } catch InsertionError.unavailable {}
        precondition(InsertionFixture.text == "Before. " && InsertionFixture.axWrites == 0 && InsertionFixture.pastes == 0)
        print("Non-text controls: rejected without writes")
        for publication in 0..<4 {
            InsertionFixture.reset(web: true)
            InsertionFixture.keyboardPublicationDelay = 3
            InsertionFixture.publishesCaretFirst = publication != 0
            InsertionFixture.publishesPartialInput = publication >= 2
            InsertionFixture.publishesDeletionFirst = publication == 3
            let delayedWriter = try LiveTextWriter(target: target())
            do {
                for words in ["Hello", "Hello. 🍦", "A longer corrected phrase with 🍦", "", "e\u{301} 🧑🏽‍💻"] {
                    try await delayedWriter.updateInEditor(words)
                    precondition(InsertionFixture.text == "Before. " + words)
                }
            } catch {
                throw NSError(domain: "Unchanged field rejected while Voco's own text/caret update settles: \(error.localizedDescription)", code: 1)
            }
            precondition(InsertionFixture.pastes == 0)
            precondition(NSPasteboard.general.string(forType: .string) == "Original clipboard")
        }
        print("Unchanged web field: delayed text, caret, and partial Unicode input survive live revisions")

        InsertionFixture.reset(web: true)
        InsertionFixture.normalizesSpaces = true
        let richWriter = try LiveTextWriter(target: target())
        for words in ["Hello world", "Hello there. 🍦", "", "Goodbye\u{00A0}world"] {
            try await richWriter.updateInEditor(words)
            precondition(InsertionFixture.text == ("Before. " + words).replacingOccurrences(of: " ", with: "\u{00A0}"))
        }
        try richWriter.commit()
        try await richWriter.updateInEditor(" Next phrase.")
        precondition(InsertionFixture.text == "Before.\u{00A0}Goodbye\u{00A0}world\u{00A0}Next\u{00A0}phrase.")
        InsertionFixture.text = InsertionFixture.text.replacingOccurrences(of: "\u{00A0}", with: " ")
        do {
            try await richWriter.updateInEditor(" Unsafe")
            preconditionFailure("A later user whitespace edit must not be mistaken for editor normalization")
        } catch InsertionError.focusChanged {}
        precondition(InsertionFixture.text == "Before. Goodbye world Next phrase.")
        precondition(InsertionFixture.pastes == 0)
        print("Rich-text space normalization: corrections, explicit non-breaking spaces, continuation, and later edit rejection")

        InsertionFixture.reset(web: true)
        InsertionFixture.normalizesSpaces = true
        InsertionFixture.usesEmptyParagraphPlaceholder = true
        InsertionFixture.text = "\n"
        InsertionFixture.selection = CFRange(location: 0, length: 0)
        let emptyRichWriter = try LiveTextWriter(target: target())
        for words in ["Hello world ", "Hi", "", "Goodbye "] {
            try await emptyRichWriter.updateInEditor(words)
            precondition(InsertionFixture.text == (words.isEmpty ? "\n" : words.replacingOccurrences(of: " ", with: "\u{00A0}")))
        }
        try emptyRichWriter.commit()
        precondition(InsertionFixture.pastes == 0)
        print("Empty rich paragraphs: placeholder and space normalization work together")

        for changesText in [false, true] {
            InsertionFixture.reset(web: true)
            let guardedWriter = try LiveTextWriter(target: target())
            InsertionFixture.onKeyboardEvent = {
                if changesText { InsertionFixture.text += " user edit" }
                else { InsertionFixture.selection = CFRange(location: 0, length: 0) }
            }
            do {
                try await guardedWriter.updateInEditor(String(repeating: "x", count: 80))
                preconditionFailure("Unrelated text or caret changes must stop subsequent keyboard batches")
            } catch InsertionError.focusChanged {}
            precondition(InsertionFixture.keyboardEvents == 1 && InsertionFixture.pastes == 0)
            precondition(InsertionFixture.text == "Before. " + String(repeating: "x", count: 20) + (changesText ? " user edit" : ""))
        }
        InsertionFixture.reset(web: true)
        InsertionFixture.keyboardPublicationDelay = 1_000
        let stalledWriter = try LiveTextWriter(target: target())
        do {
            try await stalledWriter.updateInEditor(String(repeating: "x", count: 80))
            preconditionFailure("Unconfirmed input must time out before another batch or paste")
        } catch InsertionError.unavailable {}
        precondition(InsertionFixture.text == "Before. " + String(repeating: "x", count: 20))
        precondition(InsertionFixture.keyboardEvents == 1 && InsertionFixture.pastes == 0)
        print("Unrelated editor changes and stalled publication: no later batches or duplicate paste")
        InsertionFixture.reset(web: true)
        InsertionFixture.rejectsWrite = true
        let webWriter = try LiveTextWriter(target: target())
        for words in ["Hello", "Hello. 🍦", "Hello", ""] {
            try await webWriter.updateInEditor(words)
            precondition(InsertionFixture.text == "Before. " + words)
        }
        precondition(InsertionFixture.axWrites == 0 && InsertionFixture.pastes == 0)
        precondition(NSPasteboard.general.string(forType: .string) == "Original clipboard")
        print("Web editor: live input events, Unicode, corrections, deletion, clipboard untouched")
        try await target().insert("Hello. 🍦")
        precondition(InsertionFixture.text == "Before. Hello. 🍦")
        precondition(InsertionFixture.axWrites == 0 && InsertionFixture.pastes == 1)
        precondition(NSPasteboard.general.string(forType: .string) == "Original clipboard")
        print("Web editor advertising unsupported live writes: exact paste, once, clipboard restored")
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


        for web in [false, true] {
            InsertionFixture.reset(web: web)
            if web { InsertionFixture.keyboardPublicationDelay = 3 }
            InsertionFixture.selection = CFRange(location: 0, length: 7)
            let selectedWriter = try LiveTextWriter(target: target())
            try await selectedWriter.updateInEditor(" Added")
            try await selectedWriter.updateInEditor(" Corrected 🍦")
            precondition(InsertionFixture.text == "Before. Corrected 🍦 ")
            precondition(InsertionFixture.selection.location == 0 && InsertionFixture.selection.length == 7)
            try selectedWriter.commit()
            try await selectedWriter.updateInEditor(" Next")
            precondition(InsertionFixture.text == "Before. Corrected 🍦 Next ")
            precondition(InsertionFixture.selection.location == 0 && InsertionFixture.selection.length == 7)
        }
        InsertionFixture.reset(web: true)
        InsertionFixture.selection = CFRange(location: 0, length: 7)
        let buffered = try BufferedTextWriter(target: target())
        try await buffered.insert(" Added")
        try await buffered.insert(" Next")
        precondition(InsertionFixture.text == "Before. Added Next ")
        precondition(InsertionFixture.selection.location == 0 && InsertionFixture.selection.length == 7)
        precondition(NSPasteboard.general.string(forType: .string) == "Original clipboard")
        InsertionFixture.selection = CFRange(location: 1, length: 0)
        do {
            try await buffered.insert(" Unsafe")
            preconditionFailure("Buffered insertion must reject caret movement")
        } catch InsertionError.focusChanged {}
        precondition(InsertionFixture.text == "Before. Added Next " && InsertionFixture.pastes == 2)
        print("Native, web, and buffered writers preserve selections and reject changed anchors")

        InsertionFixture.reset(web: true)
        InsertionFixture.selection = CFRange(location: 0, length: 7)
        let canceledWriter = try LiveTextWriter(target: target())
        InsertionFixture.keyboardPublicationDelay = 3
        var canceledUpdate: Task<Void, Error>?
        InsertionFixture.onKeyboardEvent = { canceledUpdate?.cancel() }
        canceledUpdate = Task { try await canceledWriter.updateInEditor(String(repeating: "x", count: 80)) }
        do {
            try await canceledUpdate!.value
            preconditionFailure("Canceled update must stop before the next batch")
        } catch is CancellationError {}
        precondition(InsertionFixture.text == "Before." + String(repeating: "x", count: 20) + " ")
        precondition(InsertionFixture.selection.location == 0 && InsertionFixture.selection.length == 7)
        precondition(InsertionFixture.keyboardEvents == 1)
        print("Canceled keyboard update: drains one posted event, preserves selection, sends no later batches")

        InsertionFixture.reset()
        let writer = try LiveTextWriter(target: target())
        try writer.update("Hello")
        try writer.update("Hello. 🍦")
        precondition(InsertionFixture.text == "Before. Hello. 🍦" && InsertionFixture.pastes == 0)
        print("Native live correction: exact text and Unicode preserved")

        for rejects in [true, false] {
            InsertionFixture.reset()
            InsertionFixture.rejectsWrite = rejects
            InsertionFixture.ignoresWrite = !rejects
            let writer = try LiveTextWriter(target: target())
            do {
                try writer.update("Hello.")
                preconditionFailure("Unsupported initial write must allow buffering")
            } catch InsertionError.liveUnsupported {}
            precondition(InsertionFixture.text == "Before. " && InsertionFixture.selection.location == 8)
            try await target().insert("Hello.")
            precondition(InsertionFixture.text == "Before. Hello." && InsertionFixture.pastes == 1)
        }
        print("Rejected and ignored initial writes: safe buffered fallback")

        InsertionFixture.reset()
        let laterFailure = try LiveTextWriter(target: target())
        try laterFailure.update("Hello")
        InsertionFixture.ignoresWrite = true
        do {
            try laterFailure.update("Hello.")
            preconditionFailure("Existing live words must not be duplicated by fallback")
        } catch InsertionError.unavailable {}
        precondition(InsertionFixture.text == "Before. Hello" && InsertionFixture.pastes == 0)

        InsertionFixture.reset()
        InsertionFixture.partialWrite = true
        do {
            let writer = try LiveTextWriter(target: target())
            try writer.update("Hello.")
            preconditionFailure("A partial write must not be retried as paste")
        } catch InsertionError.unavailable {}
        precondition(InsertionFixture.text == "Before. Wrong" && InsertionFixture.pastes == 0)
        print("Partial writes and failed corrections: recovery without duplicate paste")

        InsertionFixture.reset()
        InsertionFixture.unreadableAfterWrite = true
        do {
            let writer = try LiveTextWriter(target: target())
            try writer.update("Hello.")
            preconditionFailure("An unreadable result must not retry an already inserted phrase")
        } catch InsertionError.unavailable {}
        precondition(InsertionFixture.text == "Before. Hello." && InsertionFixture.pastes == 0)
        InsertionFixture.reset()
        InsertionFixture.rejectsSelection = true
        do {
            let writer = try LiveTextWriter(target: target())
            try writer.update("Hello.")
            preconditionFailure("Rejected initial selection must allow buffering")
        } catch InsertionError.liveUnsupported {}
        precondition(InsertionFixture.text == "Before. " && InsertionFixture.axWrites == 0)
        print("Rejected selection and unreadable write result: safe retry decisions")

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
