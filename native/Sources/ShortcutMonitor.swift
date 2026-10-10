import AppKit
import ApplicationServices
import VocoCore

@MainActor
final class ShortcutMonitor {
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
        let otherFlags: NSEvent.ModifierFlags = [.command, .control, .shift, .option]
        if let action = gesture.update(
            triggerDown: flags.contains(.function),
            otherModifier: !flags.intersection(otherFlags).isEmpty,
            keyPressed: type == .keyDown
        ) { onAction?(action) }
    }
}
