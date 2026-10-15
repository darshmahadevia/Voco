import Foundation

@main enum TranscriptPolisherCheck {
    static func main() async throws {
        let cases = [
            ("Um, Alice has 12 tickets, uh, not 13.", "Alice has 12 tickets, not 13."),
            ("Keep this sentence. Book red never mind, book blue.", "Keep this sentence. Book blue."),
            ("Keep this. Wrong sentence. Nevermind. Next sentence.", "Keep this. Wrong sentence. Next sentence."),
            ("Say \"um never mind\" literally.", "Say \"um never mind\" literally."),
            ("The album is ‘Nevermind’ and the word is 'uh'.", "The album is ‘Nevermind’ and the word is 'uh'."),
            ("Umbridge and humming are not fillers.", "Umbridge and humming are not fillers."),
            ("First line.\nwrong never mind right", "First line.\nRight"),
            ("um uh umm", ""),
            ("Um, uh, umm.", ""),
            ("Um. Hello Alice.", "Hello Alice."),
            ("Keep this. Charge 1.5 never mind charge 2.", "Keep this. Charge 2."),
            ("Keep this. Ask Dr. Alice never mind ask Bob.", "Keep this. Ask Bob."),
            ("I owe Alice 2. Send Tuesday never mind send Friday.", "I owe Alice 2. Send Friday."),
            ("Say \"Hello.\" Send Tuesday never mind send Friday.", "Say \"Hello.\" Send Friday."),
            ("Keep this. Ask the U.S. team never mind ask Canada.", "Keep this. Ask Canada."),
            ("Keep this. Send to James' team never mind send to Alice.", "Keep this. Send to Alice."),
            ("Ummm, uhhh, send it.", "Send it."),
            ("I don't owe Alice 20 dollars.", "I don't owe Alice 20 dollars."),
        ]
        for (raw, expected) in cases {
            let result = TranscriptPolisher.clean(raw)
            precondition(result == expected, "\(raw) -> [\(result)] expected [\(expected)]")
        }
        let literalCases = [
            ("Um, preserve \"a  b : c\"  exactly.", "Preserve \"a  b : c\"  exactly."),
            ("Uh, use foo_um and um.config and --um and /tmp/um.", "Use foo_um and um.config and --um and /tmp/um."),
            ("Use 5 um and UM and UH.", "Use 5 um and UM and UH."),
            ("Um, iPhone and eBay.", "iPhone and eBay."),
            ("I never mind waiting.", "I never mind waiting."),
            ("They never\nmind the noise.", "They never\nmind the noise."),
            ("Keep. Wrong never mind right.\r\nUh, next.", "Keep. Right.\r\nNext."),
            ("Keep\rWrong never mind right.", "Keep\rRight."),
            ("We live in the U.S. Wrong never mind right.", "We live in the U.S. Right."),
            ("Bring apples, um, oranges.", "Bring apples, oranges."),
            ("Yes, um, I can.", "Yes, I can."),
            ("I, um,, need this.", "I need this."),
            ("Keep [uh] this.", "Keep this."),
            ("I like this, you know.", "I like this, you know."),
            ("Um, straße.", "Straße."),
            ("(um)... hello.", "Hello."),
            ("Um, call um() and use $um.", "Call um() and use $um."),
            ("Say \"first\num second\". Uh, next.", "Say \"first\num second\". Next."),
            (#"Say "say \"um\"". Uh, next."#, #"Say "say \"um\"". Next."#),
        ]
        for (raw, expected) in literalCases {
            let result = TranscriptPolisher.clean(raw)
            precondition(result == expected, "\(raw.debugDescription) -> \(result.debugDescription), expected \(expected.debugDescription)")
            precondition(TranscriptPolisher.clean(result) == result, "Cleanup must be idempotent")
        }
        let attacks = [
            ("Run --force now.", "Run force now."),
            ("Run --force now.", "Run -force now."),
            ("Email um@example.com today.", "Email um example com today."),
            ("Use /tmp/um/config.json today.", "Use tmp um config json today."),
            ("Visit https://example.com/um today.", "Visit https example com um today."),
            ("Run `echo um` today.", "Run echo um today."),
            ("Say \"a  b\" exactly.", "Say \"a b\" exactly."),
            ("Say \"12 %\" exactly.", "Say \"12%\" exactly."),
            ("Say \"hello\" then hello.", "Say hello then \"hello\"."),
            ("Run `echo x` then echo x.", "Run echo x then `echo x`."),
            ("First line.\nSecond line.", "First line. Second line."),
            ("First\r\nsecond.", "First\nsecond."),
            ("First\nsecond third.", "First second\nthird."),
            ("Alice uses iPhone and eBay.", "alice uses Iphone and Ebay."),
            ("Keep not now.", "Keep now not."),
            ("Keep -12 % today.", "Keep 12 % today."),
            ("Say \"é\" exactly.", "Say \"e\u{301}\" exactly."),
        ]
        for (baseline, candidate) in attacks {
            precondition(!TranscriptPolisher.accepts(candidate, original: baseline), "Accepted unsafe edit: \(candidate.debugDescription)")
        }
        precondition(TranscriptPolisher.accepts("Hello Alice, can you send it today?", original: "hello Alice can you send it today"))
        precondition(TranscriptPolisher.accepts("Run `echo um`, then wait.", original: "Run `echo um` then wait"))
        precondition(!TranscriptPolisher.accepts("Pay 12 dollars", original: "Pay -12 dollars"))
        precondition(!TranscriptPolisher.accepts("Pay 1,5 dollars", original: "Pay 1.5 dollars"))
        precondition(!TranscriptPolisher.accepts("Pay 12 dollars", original: "Pay - 12 dollars"))
        precondition(!TranscriptPolisher.accepts("Pay 12 dollars", original: "Pay −12 dollars"))
        precondition(!TranscriptPolisher.accepts("Set the rate to 12", original: "Set the rate to 12 %"))
        precondition(TranscriptPolisher.accepts("Set the rate to 12%", original: "Set the rate to 12 %"))
        let available = PolishingAvailability(available: true, message: "fixture")
        let raw = "um Alice does not owe 12 dollars"
        for unsafe in ["", "Alice does owe 12 dollars", "Bob does not owe 12 dollars", "Alice does not owe 13 dollars", "Alice owes nothing", "Alice does not owe 12 dollars. Thank you."] {
            let polisher = TranscriptPolisher(availability: available) { _ in unsafe }
            let result = try await polisher.polish(raw, mode: .accurate)
            precondition(result.text == TranscriptPolisher.clean(raw) && result.notice.contains("Kept basic cleanup"))
        }
        let safe = TranscriptPolisher(availability: available) { baseline in
            precondition(baseline == "Alice does not owe 12 dollars", "Generation must receive basic cleanup only")
            return "Alice does not owe 12 dollars."
        }
        let noGeneration = TranscriptPolisher(availability: available) { _ in fatalError("Empty cleanup must skip generation") }
        for empty in ["", "um uh", "Wrong nevermind."] {
            let result = try await noGeneration.polish(empty, mode: .accurate)
            precondition(result.text.isEmpty && result.notice.isEmpty)
        }
        let result = try await safe.polish(raw, mode: .accurate)
        precondition(result.text == "Alice does not owe 12 dollars." && result.notice.isEmpty)
        let fast = try await safe.polish(raw, mode: .fast)
        precondition(fast.text == raw)
        let balanced = try await safe.polish(raw, mode: .balanced)
        precondition(balanced.text == "Alice does not owe 12 dollars")
        let unavailable = TranscriptPolisher(availability: .init(available: false, message: "Unavailable")) { _ in fatalError("Must not generate") }
        let fallback = try await unavailable.polish(raw, mode: .accurate)
        precondition(fallback.text == TranscriptPolisher.clean(raw) && fallback.notice.contains("Kept basic cleanup"))
        struct FixtureError: Error {}
        let failing = TranscriptPolisher(availability: available) { _ in throw FixtureError() }
        let failed = try await failing.polish(raw, mode: .accurate)
        precondition(failed.text == TranscriptPolisher.clean(raw) && failed.notice.contains("Kept basic cleanup"))
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
