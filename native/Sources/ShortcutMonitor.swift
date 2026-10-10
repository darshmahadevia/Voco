import AppKit
import ApplicationServices
import VocoCore

@MainActor
final class ShortcutMonitor {
    var onAction: ((HoldAction) -> Void)?
    var onEscape: (() -> Void)?
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var gesture = HoldGesture()
    private var consumedSpace = false
    var isRunning: Bool { eventTap.map { CGEvent.tapIsEnabled(tap: $0) } ?? false }

    func start() -> Bool {
        guard AXIsProcessTrusted() else { return false }
        guard !isRunning else { return true }
        stop()
        let mask = [CGEventType.flagsChanged, .keyDown, .keyUp].reduce(CGEventMask(0)) {
            $0 | (CGEventMask(1) << $1.rawValue)
        }
        let reference = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
                                         options: .defaultTap, eventsOfInterest: mask, callback: { _, type, event, reference in
            guard let reference else { return Unmanaged.passUnretained(event) }
            let monitor = Unmanaged<ShortcutMonitor>.fromOpaque(reference).takeUnretainedValue()
            let consume = MainActor.assumeIsolated {
                if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                    monitor.gesture = HoldGesture()
                    monitor.consumedSpace = false
                    DispatchQueue.main.async { [weak monitor] in monitor?.onEscape?() }
                    if let tap = monitor.eventTap { CGEvent.tapEnable(tap: tap, enable: true) }
                    return false
                }
                return monitor.handle(type: type, event: event)
            }
            return consume ? nil : Unmanaged.passUnretained(event)
        }, userInfo: reference), let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            return false
        }
        eventTap = tap
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    func stop() {
        if let source = runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        if let tap = eventTap { CFMachPortInvalidate(tap) }
        eventTap = nil
        runLoopSource = nil
        gesture = HoldGesture()
        consumedSpace = false
    }

    private func handle(type: CGEventType, event: CGEvent) -> Bool {
        guard event.getIntegerValueField(.eventSourceUserData) != vocoInsertionEventMarker else { return false }
        let flags = event.flags
        let code = event.getIntegerValueField(.keyboardEventKeycode)
        let isSpace = code == 49
        let otherFlags: CGEventFlags = [.maskCommand, .maskControl, .maskShift, .maskAlternate]
        let otherModifier = !flags.intersection(otherFlags).isEmpty
        let triggerDown = flags.contains(.maskSecondaryFn)
        if type == .keyDown && code == 53 { DispatchQueue.main.async { [weak self] in self?.onEscape?() } }
        let consume = isSpace && ((type == .keyDown && triggerDown && !otherModifier) || consumedSpace)
        if isSpace && type == .keyDown && consume { consumedSpace = true }
        if isSpace && type == .keyUp { consumedSpace = false }
        if let action = gesture.update(
            triggerDown: triggerDown,
            otherModifier: otherModifier,
            keyPressed: type == .keyDown,
            spacePressed: type == .keyDown && isSpace,
            spaceReleased: type == .keyUp && isSpace,
            isRepeat: event.getIntegerValueField(.keyboardEventAutorepeat) != 0
        ) {
            // Focus capture can block in Accessibility. Keep the event tap callback brief.
            DispatchQueue.main.async { [weak self] in self?.onAction?(action) }
        }
        return consume
    }
}
