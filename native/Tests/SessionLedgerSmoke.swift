import Foundation

@main
enum SessionLedgerSmoke {
    static func main() {
        let originalSession = UUID()
        var gate = SessionIDGate()
        gate.begin(originalSession)
        check(gate.accepts(originalSession), "current session accepts its transcript")

        check(TranscriptText.join(["Hello", ",", "world", "!"]) == "Hello, world!", "punctuation joins without extra spaces")
        check(TranscriptText.join(["", "  Hello ", "world.  ", ""]) == "Hello world.", "empty lines and outer whitespace are ignored")

        let nextSession = UUID()
        gate.invalidate()
        gate.begin(nextSession)
        check(!gate.accepts(originalSession) && gate.accepts(nextSession), "stale session callback is rejected")
        print("PASS — native session ledger")
    }

    private static func check(_ condition: Bool, _ message: String) {
        guard condition else { fatalError("Failed: \(message)") }
    }
}
