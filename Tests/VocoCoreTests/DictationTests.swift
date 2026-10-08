import Testing
import Foundation
@testable import VocoCore

@Test func holdEmitsOneStartAndOneRelease() {
    var gesture = HoldGesture()
    #expect(gesture.update(triggerDown: true) == .pressed)
    #expect(gesture.update(triggerDown: true) == nil)
    #expect(gesture.update(triggerDown: false) == .released)
    #expect(gesture.update(triggerDown: false) == nil)
}

@Test func keyboardCombinationCancelsUntilTheTriggerIsReleased() {
    var gesture = HoldGesture()
    #expect(gesture.update(triggerDown: true) == .pressed)
    #expect(gesture.update(triggerDown: true, keyPressed: true) == .cancelled)
    #expect(gesture.update(triggerDown: true) == nil)
    #expect(gesture.update(triggerDown: false) == nil)
    #expect(gesture.update(triggerDown: true) == .pressed)
}

@Test func existingModifierCombinationDoesNotStartDictation() {
    var gesture = HoldGesture()
    #expect(gesture.update(triggerDown: true, otherModifier: true) == nil)
    #expect(gesture.update(triggerDown: false) == nil)
    #expect(gesture.update(triggerDown: true) == .pressed)
}

@Test func revisedWordsReplaceTheProvisionalTranscript() {
    var transcript = Transcript()
    transcript.update(start: 0, end: 1, text: "I scream", isFinal: false)
    transcript.update(start: 0, end: 1.2, text: "Ice cream.", isFinal: true)
    #expect(transcript.text == "Ice cream.")
    #expect(transcript.finalText == "Ice cream.")
}

@Test func committedAndProvisionalWordsDoNotDuplicate() {
    var transcript = Transcript()
    transcript.update(start: 0, end: 1, text: "Hello", isFinal: true)
    transcript.update(start: 1, end: 2, text: "word", isFinal: false)
    #expect(transcript.text == "Hello word")
    #expect(transcript.finalText == "Hello")
    transcript.update(start: 1, end: 2.1, text: "world.", isFinal: true)
    transcript.update(start: 0, end: 1, text: "Wrong", isFinal: false)
    #expect(transcript.finalText == "Hello world.")
    #expect(transcript.text == "Hello world.")
}

@Test func overlappingRevisionAndOutOfOrderSegmentsProduceOneTranscript() {
    var transcript = Transcript()
    transcript.update(start: 3, end: 4, text: "tomorrow.", isFinal: true)
    transcript.update(start: 0, end: 2, text: "See you today", isFinal: false)
    transcript.update(start: 0, end: 3, text: "See you", isFinal: true)
    #expect(transcript.finalText == "See you tomorrow.")
}

@Test func pausesInsertOnlyAfterSpeechAndTextHaveSettled() {
    var gate = PauseGate()
    #expect(!gate.shouldInsert(at: 10, pause: 1.5))
    gate.receivedText(at: 10)
    #expect(!gate.shouldInsert(at: 11.4, pause: 1.5))
    gate.heardSpeech(at: 11.4)
    #expect(!gate.shouldInsert(at: 12.5, pause: 1.5))
    #expect(gate.shouldInsert(at: 12.9, pause: 1.5))
    gate.inserted()
    #expect(!gate.shouldInsert(at: 20, pause: 1.5))
    gate.receivedText(at: 21)
    #expect(gate.shouldInsert(at: 22.5, pause: 1.5))
}

@Test func pauseBatchesDoNotRepeatAlreadyInsertedWords() {
    var transcript = Transcript()
    transcript.update(start: 0, end: 1, text: "First sentence.", isFinal: true)
    let first = transcript.finalized(after: -1)
    #expect(first.text == "First sentence.")
    #expect(transcript.finalized(after: first.end).text == "")
    transcript.update(start: 2, end: 3, text: "Second sentence", isFinal: false)
    #expect(transcript.text(after: first.end) == "Second sentence")
    #expect(transcript.finalized(after: first.end).text == "")
    transcript.update(start: 2, end: 3.1, text: "Second sentence.", isFinal: true)
    let second = transcript.finalized(after: first.end)
    #expect(second.text == "Second sentence.")
    #expect(transcript.text(after: second.end) == "")
    #expect(transcript.finalized(after: second.end).text == "")
}

@Test func liveWordsAreCorrectedWithoutReplacingSurroundingText() throws {
    var buffer = try LiveTextBuffer(document: "Start | end", selection: NSRange(location: 6, length: 0))
    let first = try #require(try buffer.plan(text: "I scream", document: "Start | end", selection: NSRange(location: 6, length: 0)))
    #expect(first.document == "Start I scream| end")
    try buffer.accept(first, document: "Start I scream| end", selection: NSRange(location: 14, length: 0))
    let correction = try #require(try buffer.plan(text: "Ice cream.", document: "Start I scream| end", selection: NSRange(location: 14, length: 0)))
    #expect(correction.range == NSRange(location: 7, length: 7))
    #expect(correction.replacement == "ce cream.")
    #expect(correction.document == "Start Ice cream.| end")
    try buffer.accept(correction, document: "Start Ice cream.| end", selection: NSRange(location: 16, length: 0))
    let emoji = try #require(try buffer.plan(text: "Ice cream. 🍦", document: "Start Ice cream.| end", selection: NSRange(location: 16, length: 0)))
    #expect(emoji.range == NSRange(location: 16, length: 0))
    #expect(emoji.document == "Start Ice cream. 🍦| end")
    #expect(emoji.selection == NSRange(location: 19, length: 0))
}

@Test func liveTypingStopsWhenTheUserMovesTheCaretOrEditsTheDocument() throws {
    let buffer = try LiveTextBuffer(document: "Existing", selection: NSRange(location: 8, length: 0))
    #expect(throws: LiveTextError.changed) {
        try buffer.plan(text: "Hello", document: "Existing", selection: NSRange(location: 0, length: 0))
    }
    #expect(throws: LiveTextError.changed) {
        try buffer.plan(text: "Hello", document: "Existing!", selection: NSRange(location: 8, length: 0))
    }
}

@Test func liveDictationReplacesTheInitialSelectionAndRejectsUnverifiedWrites() throws {
    var buffer = try LiveTextBuffer(document: "Replace old text", selection: NSRange(location: 8, length: 3))
    let plan = try #require(try buffer.plan(text: "new", document: "Replace old text", selection: NSRange(location: 8, length: 3)))
    #expect(plan.document == "Replace new text")
    #expect(throws: LiveTextError.changed) {
        try buffer.accept(plan, document: "Replace old text", selection: NSRange(location: 11, length: 0))
    }
    #expect(throws: LiveTextError.invalidRange) {
        try LiveTextBuffer(document: "Short", selection: NSRange(location: 10, length: 0))
    }
}

@Test func continuousShortcutTogglesOnceAndConsumesTheWholeSpacePress() {
    var shortcut = ContinuousShortcut()
    #expect(shortcut.spaceDown(fnDown: true, otherModifier: false, repeated: false) == .toggle)
    #expect(shortcut.spaceDown(fnDown: true, otherModifier: false, repeated: true) == .consume)
    #expect(shortcut.spaceDown(fnDown: false, otherModifier: false, repeated: true) == .consume)
    #expect(shortcut.spaceUp() == .consume)
    #expect(shortcut.spaceDown(fnDown: false, otherModifier: false, repeated: false) == .pass)
    #expect(shortcut.spaceUp() == .pass)
    #expect(shortcut.spaceDown(fnDown: true, otherModifier: false, repeated: false) == .toggle)
}

@Test func ordinaryShortcutsAndAnAlreadyRepeatingKeyDoNotToggleDictation() {
    var shortcut = ContinuousShortcut()
    #expect(shortcut.spaceDown(fnDown: true, otherModifier: true, repeated: false) == .pass)
    #expect(shortcut.spaceUp() == .pass)
    #expect(shortcut.spaceDown(fnDown: true, otherModifier: false, repeated: true) == .consume)
    #expect(shortcut.spaceUp() == .consume)
}
