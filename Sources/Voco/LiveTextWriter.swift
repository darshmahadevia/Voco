import AppKit
import ApplicationServices
import VocoCore

@MainActor
final class LiveTextWriter {
    private let target: FocusTarget
    private let element: AXUIElement
    private var buffer: LiveTextBuffer
    private var currentText = ""

    init(target: FocusTarget) throws {
        self.target = target
        element = try target.validate()
        for attribute in [kAXSelectedTextAttribute, kAXSelectedTextRangeAttribute] {
            var writable = DarwinBoolean(false)
            guard AXUIElementIsAttributeSettable(element, attribute as CFString, &writable) == .success,
                  writable.boolValue else { throw InsertionError.liveUnsupported }
        }
        let snapshot = try Self.snapshot(element)
        do { buffer = try LiveTextBuffer(document: snapshot.text, selection: snapshot.selection) }
        catch { throw InsertionError.liveUnsupported }
    }

    func update(_ text: String) throws {
        _ = try target.validate()
        let snapshot = try Self.snapshot(element)
        let plan: LiveTextPlan?
        do { plan = try buffer.plan(text: text, document: snapshot.text, selection: snapshot.selection) }
        catch { throw InsertionError.focusChanged }
        guard let plan else { return }
        try setSelection(plan.range)
        guard AXUIElementSetAttributeValue(element, kAXSelectedTextAttribute as CFString, plan.replacement as CFString) == .success
        else { throw InsertionError.unavailable }
        // Text replacement does not consistently advance the caret across apps.
        try setSelection(plan.selection)
        let actual = try Self.snapshot(element)
        do { try buffer.accept(plan, document: actual.text, selection: actual.selection) }
        catch { throw InsertionError.unavailable }
        currentText = text
    }

    func commit() throws {
        _ = try target.validate()
        let snapshot = try Self.snapshot(element)
        do { _ = try buffer.plan(text: currentText, document: snapshot.text, selection: snapshot.selection) }
        catch { throw InsertionError.focusChanged }
        buffer = try LiveTextBuffer(document: snapshot.text, selection: snapshot.selection)
        currentText = ""
    }

    private func setSelection(_ selection: NSRange) throws {
        var range = CFRange(location: selection.location, length: selection.length)
        guard let value = AXValueCreate(.cfRange, &range),
              AXUIElementSetAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, value) == .success
        else { throw InsertionError.unavailable }
    }

    private static func snapshot(_ element: AXUIElement) throws -> (text: String, selection: NSRange) {
        var value: CFTypeRef?, rangeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &value) == .success,
              let text = value as? String,
              AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &rangeValue) == .success,
              let rangeValue, CFGetTypeID(rangeValue) == AXValueGetTypeID()
        else { throw InsertionError.liveUnsupported }
        var range = CFRange()
        guard AXValueGetValue(rangeValue as! AXValue, .cfRange, &range) else { throw InsertionError.liveUnsupported }
        return (text, NSRange(location: range.location, length: range.length))
    }
}
