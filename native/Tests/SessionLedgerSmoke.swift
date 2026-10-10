import Foundation

@main
enum SessionLedgerSmoke {
    static func main() {
        let originalSession = UUID()
        var gate = SessionIDGate()
        gate.begin(originalSession)
        check(gate.accepts(originalSession), "current session accepts its transcript")

        var ledger = TranscriptLedger()
        let partial = SpeechLine(text: "The quick brow", complete: false)
        ledger.update([partial])
        check(ledger.text == "The quick brow", "partial transcript remains visible")

        let correction = SpeechLine(text: "The quick brown fox.", complete: false)
        ledger.update([correction])
        check(ledger.text == "The quick brown fox.", "latest snapshot replaces the partial transcript")
        ledger.update([])
        check(ledger.text == "The quick brown fox.", "empty final update retains the last partial")

        let firstFinal = SpeechLine(text: "The quick brown fox.", complete: true)
        ledger.update([firstFinal])

        let secondPartial = SpeechLine(text: "This is a local", complete: false)
        ledger.update([firstFinal, secondPartial])
        check(ledger.text == "The quick brown fox. This is a local", "pause continuation keeps both lines")

        let secondFinal = SpeechLine(text: "This is a local test.", complete: true)
        ledger.update([firstFinal, secondFinal])

        check(ledger.text == "The quick brown fox. This is a local test.", "final transcript contains both phrases")
        check(TranscriptLedger.join(["Hello", ",", "world", "!"]) == "Hello, world!", "punctuation joins without extra spaces")
        check(TranscriptLedger.join(["", "  Hello ", "world.  ", ""]) == "Hello world.", "empty lines and outer whitespace are ignored")

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
