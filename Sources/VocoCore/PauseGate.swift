public struct PauseGate: Sendable {
    private var lastActivity: Double?
    private var hasPendingText = false

    public init() {}

    public mutating func heardSpeech(at time: Double) { lastActivity = time }

    public mutating func receivedText(at time: Double) {
        lastActivity = time
        hasPendingText = true
    }

    public func shouldInsert(at time: Double, pause: Double) -> Bool {
        guard hasPendingText, let lastActivity else { return false }
        return time - lastActivity >= pause
    }

    public mutating func inserted() { hasPendingText = false }
}
