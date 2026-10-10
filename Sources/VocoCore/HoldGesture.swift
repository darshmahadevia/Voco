public enum HoldAction: Sendable, Equatable {
    case pressed
    case released
    case cancelled
    case toggleContinuous
}

public struct HoldGesture: Sendable {
    private enum TriggerState { case idle, held, blocked, chord }
    private var trigger: TriggerState = .idle
    private var spaceDown = false

    public init() {}

    public mutating func update(
        triggerDown: Bool,
        otherModifier: Bool = false,
        keyPressed: Bool = false,
        spacePressed: Bool = false,
        spaceReleased: Bool = false,
        isRepeat: Bool = false
    ) -> HoldAction? {
        if spaceReleased { spaceDown = false }
        if spacePressed {
            let freshPress = !spaceDown && !isRepeat
            spaceDown = true
            if triggerDown && !otherModifier && trigger != .blocked {
                guard freshPress else { return nil }
                trigger = .chord
                return .toggleContinuous
            }
        }
        if !triggerDown {
            let wasHeld = trigger == .held
            trigger = .idle
            return wasHeld ? .released : nil
        }
        if trigger == .idle {
            trigger = otherModifier || keyPressed ? .blocked : .held
            return trigger == .held ? .pressed : nil
        }
        if (trigger == .held || trigger == .chord) && (otherModifier || keyPressed) {
            trigger = .blocked
            return .cancelled
        }
        return nil
    }
}
