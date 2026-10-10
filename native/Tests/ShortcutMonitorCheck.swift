import Foundation

let vocoInsertionEventMarker: Int64 = 0x564f434f

extension ShortcutMonitor {
    fileprivate func feed(_ type: CGEventType, code: Int64 = 0, flags: CGEventFlags = [], repeated: Bool = false, inserted: Bool = false) -> Bool {
        let event = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(code), keyDown: type != .keyUp)!
        event.type = type
        event.flags = flags
        event.setIntegerValueField(.keyboardEventKeycode, value: code)
        event.setIntegerValueField(.keyboardEventAutorepeat, value: repeated ? 1 : 0)
        if inserted { event.setIntegerValueField(.eventSourceUserData, value: vocoInsertionEventMarker) }
        return handle(type: type, event: event)
    }
}

@main enum ShortcutMonitorCheck {
    @MainActor static func main() async throws {
        func settle() async throws { try await Task.sleep(for: .milliseconds(20)) }
        let monitor = ShortcutMonitor()
        var actions: [HoldAction] = []
        var escapes = 0
        monitor.onAction = { actions.append($0) }
        monitor.onEscape = { escapes += 1 }
        precondition(!monitor.feed(.keyDown, code: 49))
        precondition(!monitor.feed(.keyUp, code: 49))
        precondition(actions.isEmpty)
        precondition(!monitor.feed(.flagsChanged, flags: .maskSecondaryFn))
        precondition(monitor.feed(.keyDown, code: 49, flags: .maskSecondaryFn))
        precondition(monitor.feed(.keyDown, code: 49, flags: .maskSecondaryFn, repeated: true))
        precondition(!monitor.feed(.flagsChanged))
        precondition(monitor.feed(.keyUp, code: 49))
        try await settle()
        precondition(actions == [.pressed, .toggleContinuous])
        precondition(monitor.feed(.keyDown, code: 49, flags: .maskSecondaryFn))
        precondition(monitor.feed(.keyUp, code: 49, flags: .maskSecondaryFn))
        try await settle()
        precondition(actions == [.pressed, .toggleContinuous, .toggleContinuous])
        precondition(!monitor.feed(.keyDown, code: 53, flags: .maskSecondaryFn))
        try await settle()
        precondition(escapes == 1)
        monitor.stop()
        actions = []
        precondition(!monitor.feed(.keyDown, code: 49, flags: .maskSecondaryFn, inserted: true))
        precondition(actions.isEmpty)
        precondition(!monitor.feed(.flagsChanged, flags: [.maskSecondaryFn, .maskCommand]))
        precondition(!monitor.feed(.keyDown, code: 49, flags: [.maskSecondaryFn, .maskCommand]))
        precondition(actions.isEmpty)
        monitor.stop()
        actions = []
        precondition(!monitor.feed(.keyDown, code: 49))
        precondition(!monitor.feed(.flagsChanged, flags: .maskSecondaryFn))
        precondition(monitor.feed(.keyDown, code: 49, flags: .maskSecondaryFn, repeated: true))
        precondition(!monitor.feed(.flagsChanged))
        precondition(monitor.feed(.keyUp, code: 49))
        try await settle()
        precondition(actions == [.pressed, .released])
        print("PASS shortcut monitor: chord down/up suppression, repeats, Fn release, fresh chord, Escape, inserted events, other modifiers")
    }
}
