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
    var onContinuousToggle: (() -> Void)?
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var gesture = HoldGesture()
    private var shortcutTap: CFMachPort?
    private var shortcutSource: CFRunLoopSource?
    private var spaceGesture = ContinuousShortcut()

    var isRunning: Bool { globalMonitor != nil && localMonitor != nil && shortcutTap != nil }

    func start() -> Bool {
        guard AXIsProcessTrusted() else { return false }
        guard !isRunning else { return true }
        stop()
        let eventMask = (CGEventMask(1) << CGEventType.keyDown.rawValue) | (CGEventMask(1) << CGEventType.keyUp.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
            eventsOfInterest: eventMask, callback: Self.filterShortcut,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ), let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        else { return false }
        shortcutTap = tap
        shortcutSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
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
        if let shortcutSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), shortcutSource, .commonModes) }
        if let shortcutTap { CFMachPortInvalidate(shortcutTap) }
        shortcutTap = nil
        shortcutSource = nil
        spaceGesture = ContinuousShortcut()
        gesture = HoldGesture()
    }

    nonisolated private static let filterShortcut: CGEventTapCallBack = { _, type, event, context in
        guard let context else { return Unmanaged.passUnretained(event) }
        let monitor = Unmanaged<ShortcutMonitor>.fromOpaque(context).takeUnretainedValue()
        let code = event.getIntegerValueField(.keyboardEventKeycode)
        let flags = event.flags
        let repeated = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
        let suppress = MainActor.assumeIsolated {
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                if let tap = monitor.shortcutTap { CGEvent.tapEnable(tap: tap, enable: true) }
                monitor.spaceGesture = ContinuousShortcut()
                return false
            }
            guard code == 49 else {
                return false
            }
            let other: CGEventFlags = [.maskCommand, .maskControl, .maskAlternate, .maskShift]
            let action = type == .keyUp ? monitor.spaceGesture.spaceUp()
                : monitor.spaceGesture.spaceDown(fnDown: flags.contains(.maskSecondaryFn),
                                                  otherModifier: !flags.intersection(other).isEmpty, repeated: repeated)
            if action == .toggle {
                Task { @MainActor [weak monitor] in monitor?.onContinuousToggle?() }
            }
            return action != .pass
        }
        return suppress ? nil : Unmanaged.passUnretained(event)
    }

    nonisolated private static func receive(_ event: NSEvent, for monitor: ShortcutMonitor) {
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
