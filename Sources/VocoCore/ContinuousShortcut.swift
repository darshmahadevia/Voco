public enum ContinuousKeyAction: Sendable, Equatable { case pass, consume, toggle }

public struct ContinuousShortcut: Sendable {
    private var captured = false
    public init() {}

    public mutating func spaceDown(fnDown: Bool, otherModifier: Bool, repeated: Bool) -> ContinuousKeyAction {
        if captured { return .consume }
        guard fnDown && !otherModifier else { return .pass }
        captured = true
        return repeated ? .consume : .toggle
    }

    public mutating func spaceUp() -> ContinuousKeyAction {
        guard captured else { return .pass }
        captured = false
        return .consume
    }
}
