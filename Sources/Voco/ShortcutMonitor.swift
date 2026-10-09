import AppKit
import ApplicationServices
import VocoCore

enum TalkKey: String, CaseIterable, Identifiable {
    case fn, rightOption, leftOption
    var id: String { rawValue }
    var label: String {
        switch self {
        case .fn: "Fn / Globe"
        case .rightOption: "Right Option"
        case .leftOption: "Left Option"
        }
    }
}

@MainActor
final class ShortcutMonitor {
    var key: TalkKey = .fn
    var onAction: ((HoldAction) -> Void)?
    var onEscape: (() -> Void)?
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var gesture = HoldGesture()
    var isRunning: Bool { globalMonitor != nil && localMonitor != nil }

    func start() -> Bool {
        guard AXIsProcessTrusted() else { return false }
        guard !isRunning else { return true }
        stop()
        let mask: NSEvent.EventTypeMask = [.flagsChanged, .keyDown]
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] event in
            guard let self else { return }
            Self.receive(event, for: self)
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            if let self { Self.receive(event, for: self) }
            return event
        }
        guard isRunning else { stop(); return false }
        return true
    }

    func stop() {
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        globalMonitor = nil
        localMonitor = nil
        gesture = HoldGesture()
    }

    nonisolated private static func receive(_ event: NSEvent, for monitor: ShortcutMonitor) {
        guard event.cgEvent?.getIntegerValueField(.eventSourceUserData) != vocoInsertionEventMarker else { return }
        let type = event.type
        let flags = event.modifierFlags
        let code = event.keyCode
        // AppKit delivers both event-monitor handlers on the main thread.
        MainActor.assumeIsolated { monitor.handle(type: type, flags: flags, code: code) }
    }

    private func handle(type: NSEvent.EventType, flags: NSEvent.ModifierFlags, code: UInt16) {
        if type == .keyDown && code == 53 { onEscape?() }
        let down: Bool
        var otherFlags: NSEvent.ModifierFlags = [.command, .control, .shift]
        switch key {
        case .fn:
            down = flags.contains(.function)
            otherFlags.insert(.option)
        case .rightOption:
            down = CGEventSource.keyState(.combinedSessionState, key: 61)
            otherFlags.insert(.function)
        case .leftOption:
            down = CGEventSource.keyState(.combinedSessionState, key: 58)
            otherFlags.insert(.function)
        }
        if let action = gesture.update(
            triggerDown: down,
            otherModifier: !flags.intersection(otherFlags).isEmpty,
            keyPressed: type == .keyDown
        ) { onAction?(action) }
    }
}
