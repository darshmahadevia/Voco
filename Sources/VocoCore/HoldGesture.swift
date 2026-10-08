public enum HoldAction: Sendable, Equatable {
    case pressed
    case released
    case cancelled
}

public struct HoldGesture: Sendable {
    private var isDown = false
    private var blocked = false

    public init() {}

    public mutating func update(
        triggerDown: Bool,
        otherModifier: Bool = false,
        keyPressed: Bool = false
    ) -> HoldAction? {
        if !triggerDown {
            let wasActive = isDown && !blocked
            isDown = false
            blocked = false
            return wasActive ? .released : nil
        }
        if !isDown {
            isDown = true
            blocked = otherModifier || keyPressed
            return blocked ? nil : .pressed
        }
        if !blocked && (otherModifier || keyPressed) {
            blocked = true
            return .cancelled
        }
        return nil
    }
}
