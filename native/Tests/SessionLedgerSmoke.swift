import Foundation

private struct FakeTextTarget {
    private(set) var value = ""

    mutating func insert(_ text: String) { value.append(text) }
}

@main
enum SessionLedgerSmoke {
    static func main() {
        check(FocusTargetPolicy.isParentProcess(42, parentProcessID: 42), "Electron parent is excluded as an insertion target")
        check(!FocusTargetPolicy.isParentProcess(43, parentProcessID: 42), "unrelated foreground target remains allowed")

        let originalSession = UUID()
        var gate = SessionIDGate()
        gate.begin(originalSession)
        check(gate.accepts(originalSession), "current session accepts its transcript")

        var ledger = TranscriptLedger()
        var target = FakeTextTarget()
        let partial = MoonshineLine(id: 1, start: 0, end: 1, text: "The quick brow", complete: false)
        ledger.update([partial])
        check(ledger.text == "The quick brow", "partial transcript remains visible")
        check(ledger.insertion(for: ledger.pendingLines).isEmpty, "provisional line is not inserted")
        check(ledger.committablePrefix.isEmpty, "provisional line cannot be committed")

        let correction = MoonshineLine(id: 1, start: 0, end: 1.4, text: "The quick brown fox.", complete: false)
        ledger.update([correction])
        check(ledger.text == "The quick brown fox.", "same line ID revises without duplication")
        ledger.update([])
        check(ledger.text == "The quick brown fox.", "empty final update retains the last partial")

        let firstFinal = MoonshineLine(id: 1, start: 0, end: 1.4, text: "The quick brown fox.", complete: true)
        ledger.update([firstFinal])
        target.insert(ledger.insertion(for: ledger.pendingLines))
        let firstPending = ledger.pendingLines
        ledger.markCommitted(firstPending)

        let secondPartial = MoonshineLine(id: 2, start: 1.5, end: 2.2, text: "This is a local", complete: false)
        ledger.update([firstFinal, secondPartial])
        check(ledger.text == "The quick brown fox. This is a local", "pause continuation keeps both lines")
        check(ledger.livePendingText == " This is a local", "live continuation includes its separator")
        check(ledger.insertion(for: [firstFinal]).isEmpty, "committed line cannot be inserted twice")

        let secondFinal = MoonshineLine(id: 2, start: 1.5, end: 2.5, text: "This is a local test.", complete: true)
        ledger.update([firstFinal, secondFinal])
        let secondPending = ledger.pendingLines
        target.insert(ledger.insertion(for: secondPending))
        ledger.markCommitted(secondPending)
        target.insert(ledger.insertion(for: ledger.pendingLines))
        check(target.value == "The quick brown fox. This is a local test.", "final phrase inserts once")
        check(ledger.text == target.value, "ledger matches inserted text")

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
