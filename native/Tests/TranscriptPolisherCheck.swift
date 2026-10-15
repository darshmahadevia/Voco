import Foundation

@main enum TranscriptPolisherCheck {
    static func main() async throws {
        let cases = [
            ("Um, Alice has 12 tickets, uh, not 13.", "Alice has 12 tickets, not 13."),
            ("Keep this sentence. Book red never mind, book blue.", "Keep this sentence. book blue."),
            ("Keep this. Wrong sentence. Nevermind. Next sentence.", "Keep this. Wrong sentence. Next sentence."),
            ("Say \"um never mind\" literally.", "Say \"um never mind\" literally."),
            ("The album is ‘Nevermind’ and the word is 'uh'.", "The album is ‘Nevermind’ and the word is 'uh'."),
            ("Umbridge and humming are not fillers.", "Umbridge and humming are not fillers."),
            ("First line.\nwrong never mind right", "First line.\nright"),
            ("um uh umm", ""),
            ("Um, uh, umm.", ""),
            ("Um. Hello Alice.", "Hello Alice."),
            ("Keep this. Charge 1.5 never mind charge 2.", "Keep this. charge 2."),
            ("Keep this. Ask Dr. Alice never mind ask Bob.", "Keep this. ask Bob."),
            ("I owe Alice 2. Send Tuesday never mind send Friday.", "I owe Alice 2. send Friday."),
            ("Say \"Hello.\" Send Tuesday never mind send Friday.", "Say \"Hello.\" send Friday."),
            ("I don't owe Alice 20 dollars.", "I don't owe Alice 20 dollars."),
        ]
        for (raw, expected) in cases {
            let result = TranscriptPolisher.clean(raw)
            precondition(result == expected, "\(raw) -> [\(result)] expected [\(expected)]")
        }
        precondition(!TranscriptPolisher.accepts("Pay 12 dollars", original: "Pay -12 dollars"))
        precondition(!TranscriptPolisher.accepts("Pay 1,5 dollars", original: "Pay 1.5 dollars"))
        precondition(!TranscriptPolisher.accepts("Pay 12 dollars", original: "Pay - 12 dollars"))
        precondition(!TranscriptPolisher.accepts("Pay 12 dollars", original: "Pay −12 dollars"))
        let available = PolishingAvailability(available: true, message: "fixture")
        let raw = "um Alice does not owe 12 dollars"
        for unsafe in ["", "Alice does owe 12 dollars", "Bob does not owe 12 dollars", "Alice does not owe 13 dollars", "Alice owes nothing", "Alice does not owe 12 dollars. Thank you."] {
            let polisher = TranscriptPolisher(availability: available) { _ in unsafe }
            let result = try await polisher.polish(raw, mode: .accurate)
            precondition(result.text == raw && !result.notice.isEmpty)
        }
        let safe = TranscriptPolisher(availability: available) { _ in "Alice does not owe 12 dollars." }
        let result = try await safe.polish(raw, mode: .accurate)
        precondition(result.text == "Alice does not owe 12 dollars." && result.notice.isEmpty)
        let fast = try await safe.polish(raw, mode: .fast)
        precondition(fast.text == raw)
        let balanced = try await safe.polish(raw, mode: .balanced)
        precondition(balanced.text == "Alice does not owe 12 dollars")
        let unavailable = TranscriptPolisher(availability: .init(available: false, message: "Unavailable")) { _ in fatalError("Must not generate") }
        let fallback = try await unavailable.polish(raw, mode: .accurate)
        precondition(fallback.text == raw && !fallback.notice.isEmpty)
        struct FixtureError: Error {}
        let failing = TranscriptPolisher(availability: available) { _ in throw FixtureError() }
        let failed = try await failing.polish(raw, mode: .accurate)
        precondition(failed.text == raw && !failed.notice.isEmpty)
        let tooLong = String(repeating: "a", count: TranscriptPolisher.maximumInputBytes + 1)
        let longResult = try await safe.polish(tooLong, mode: .accurate)
        precondition(longResult.text == tooLong && !longResult.notice.isEmpty)
        let slow = TranscriptPolisher(availability: available) { _ in
            try await Task.sleep(for: .seconds(30))
            return "late"
        }
        let task = Task { try await slow.polish(raw, mode: .accurate) }
        task.cancel()
        do { _ = try await task.value; preconditionFailure("Cancellation must throw") }
        catch is CancellationError {}
        print("PASS deterministic cleanup, literal wording, safe validation, fast/balanced, empty/unsafe/failure/unavailable/long fallback, cancellation")
        let system = TranscriptPolisher.system
        print("FoundationModels availability: \(system.availability.message)")
        if CommandLine.arguments.contains("--smoke") {
            let smoke = try await system.polish("Um, Alice has 12 tickets, not 13.", mode: .accurate)
            print("FoundationModels smoke output: \(smoke.text)")
            print("FoundationModels smoke notice: \(smoke.notice)")
        }
    }
}
