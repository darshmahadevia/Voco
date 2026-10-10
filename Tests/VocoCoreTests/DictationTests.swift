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

@Test func liveTypingKeepsUTF16OffsetsAcrossUnicodeCorrections() throws {
    var buffer = try LiveTextBuffer(document: "|tail", selection: NSRange(location: 0, length: 0))
    let first = try #require(try buffer.plan(text: "e\u{301}", document: "|tail", selection: NSRange(location: 0, length: 0)))
    try buffer.accept(first, document: first.document, selection: first.selection)

    let normalized = try #require(try buffer.plan(text: "é", document: first.document, selection: first.selection))
    #expect(normalized.range == NSRange(location: 0, length: 2))
    #expect(normalized.replacement == "é")
    #expect(Array(normalized.document.utf16) == Array("é|tail".utf16))
    #expect(normalized.selection == NSRange(location: 1, length: 0))
    try buffer.accept(normalized, document: normalized.document, selection: normalized.selection)

    let correction = try #require(try buffer.plan(text: "é!", document: normalized.document, selection: normalized.selection))
    #expect(correction.range == NSRange(location: 1, length: 0))
    #expect(correction.replacement == "!")
    #expect(Array(correction.document.utf16) == Array("é!|tail".utf16))
    #expect(correction.selection == NSRange(location: 2, length: 0))
    try buffer.accept(correction, document: correction.document, selection: correction.selection)

    let next = try #require(try buffer.plan(text: "é! x", document: correction.document, selection: correction.selection))
    #expect(Array(next.document.utf16) == Array("é! x|tail".utf16))
}

@Test func liveTypingRejectsCanonicallyEquivalentDocumentEdits() throws {
    let buffer = try LiveTextBuffer(document: "prefix|café", selection: NSRange(location: 6, length: 0))
    #expect(throws: LiveTextError.changed) {
        try buffer.plan(text: "Hello", document: "prefix|cafe\u{301}", selection: NSRange(location: 6, length: 0))
    }
}

@Test func liveTypingRejectsCanonicallyEquivalentAcceptedDocuments() throws {
    var buffer = try LiveTextBuffer(document: "|café", selection: NSRange(location: 0, length: 0))
    let plan = try #require(try buffer.plan(text: "Hello", document: "|café", selection: NSRange(location: 0, length: 0)))
    #expect(throws: LiveTextError.changed) {
        try buffer.accept(plan, document: "Hello|cafe\u{301}", selection: plan.selection)
    }
}

@Test func liveTypingRejectsSelectionsInsideSurrogatePairs() {
    #expect(throws: LiveTextError.invalidRange) {
        try LiveTextBuffer(document: "😀tail", selection: NSRange(location: 1, length: 0))
    }
    #expect(throws: LiveTextError.invalidRange) {
        try LiveTextBuffer(document: "😀tail", selection: NSRange(location: 0, length: 1))
    }
}

@Test func liveDictationPreservesTheInitialSelectionAndRejectsUnverifiedWrites() throws {
    var buffer = try LiveTextBuffer(document: "Replace old text", selection: NSRange(location: 8, length: 3))
    let plan = try #require(try buffer.plan(text: "new", document: "Replace old text", selection: NSRange(location: 8, length: 3)))
    #expect(plan.document == "Replace oldnew text")
    #expect(plan.selection == NSRange(location: 8, length: 3))
    #expect(throws: LiveTextError.changed) {
        try buffer.accept(plan, document: "Replace old text", selection: NSRange(location: 11, length: 0))
    }
    #expect(throws: LiveTextError.invalidRange) {
        try LiveTextBuffer(document: "Short", selection: NSRange(location: 10, length: 0))
    }
}

@Test func selectedTextSurvivesCorrectionsAndPauseContinuation() throws {
    var buffer = try LiveTextBuffer(document: "Before selected after", selection: NSRange(location: 7, length: 8))
    let selection = NSRange(location: 7, length: 8)
    let first = try #require(try buffer.plan(text: " I scream", document: "Before selected after", selection: selection))
    try buffer.accept(first, document: first.document, selection: selection)
    let revised = try #require(try buffer.plan(text: " Ice cream. 🍦", document: first.document, selection: selection))
    #expect(revised.document == "Before selected Ice cream. 🍦 after")
    try buffer.accept(revised, document: revised.document, selection: selection)
    try buffer.commit(document: revised.document, selection: selection)
    let next = try #require(try buffer.plan(text: " Next.", document: revised.document, selection: selection))
    #expect(next.document == "Before selected Ice cream. 🍦 Next. after")
    #expect(next.selection == selection)
}
