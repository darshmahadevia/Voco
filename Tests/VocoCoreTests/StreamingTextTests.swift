import Foundation
import Testing
@testable import VocoCore

@Test func unstableWordsStayBufferedAndTheLastWordWaitsForContext() {
    var stream = StableText()
    stream.update("I scream", now: 0)
    stream.update("Ice cream tastes good", now: 0.12)
    stream.update("Ice cream tastes good", now: 0.24)
    #expect(stream.text == "")
    stream.update("Ice cream tastes good", now: 0.36)
    #expect(stream.text == "Ice cream tastes")
    stream.update("Ice cream tastes great.", final: true, now: 0.4)
    #expect(stream.text == "Ice cream tastes great.")
}

@Test func growingHypothesesDoNotRestartTheDelayForEarlierWords() {
    var stream = StableText()
    stream.update("The quick", now: 0)
    stream.update("The quick brown", now: 0.12)
    stream.update("The quick brown fox", now: 0.24)
    #expect(stream.text == "The quick")
    stream.update("The quick brown fox jumps", now: 0.36)
    #expect(stream.text == "The quick brown")
    stream.update("The quick brown fox jumps", now: 0.48)
    #expect(stream.text == "The quick brown fox")
}

@Test func lateCorrectionsKeepQueuedWordsAndAppendOnlyNewSpeech() {
    var stream = StableText()
    stream.update("I scream tastes good", now: 0)
    stream.update("I scream tastes good", now: 0.24)
    #expect(stream.text == "I scream tastes")
    stream.update("Ice cream tastes great today", now: 0.7)
    #expect(stream.text == "I scream tastes")
    stream.update("Ice cream tastes great today.", final: true, now: 0.8)
    #expect(stream.text == "I scream tastes great today.")
    stream.update("Ice cream tastes great today.", final: true, now: 1)
    #expect(stream.text == "I scream tastes great today.")
}

@Test func addedOrRemovedWordsBeforeTheCommitBoundaryDoNotDuplicateTheTail() {
    var added = StableText()
    added.update("Turn lights in here", now: 0)
    added.update("Turn lights in here", now: 0.24)
    #expect(added.text == "Turn lights in")
    added.update("Turn the lights in here please.", final: true, now: 0.8)
    #expect(added.text == "Turn lights in here please.")

    var removed = StableText()
    removed.update("Please turn the lights on now", now: 0)
    removed.update("Please turn the lights on now", now: 0.24)
    removed.update("Turn lights on now.", final: true, now: 0.8)
    #expect(removed.text == "Please turn the lights on now.")
}

@Test func emptyAndShorterHypothesesCannotEraseOrReinsertQueuedText() {
    var stream = StableText()
    stream.update("Hello lovely world", now: 0)
    stream.update("Hello lovely world", now: 0.24)
    #expect(stream.text == "Hello lovely")
    stream.update("Hello", now: 0.7)
    stream.update("", now: 0.8)
    #expect(stream.text == "Hello lovely")
    stream.update("Hello lovely world.", final: true, now: 0.9)
    #expect(stream.text == "Hello lovely world.")
}

@Test func finalizationFlushesShortUtterancesAndPhraseContinuationExactlyOnce() {
    var stream = StableText()
    stream.update("Hello.", now: 0)
    #expect(stream.text == "")
    stream.update("Hello.", final: true, now: 0.1)
    #expect(stream.text == "Hello.")
    stream.update("Hello. Next phrase.", final: true, now: 0.2)
    #expect(stream.text == "Hello. Next phrase.")
    stream.update("hello. Next phrase.", final: true, now: 0.3)
    #expect(stream.text == "Hello. Next phrase.")
}

@Test func punctuationAndUnicodeCorrectionsCannotRewriteQueuedCharacters() {
    var stream = StableText()
    stream.update("Cafe\u{301} 🧑🏽‍💻 is nice", now: 0)
    stream.update("Cafe\u{301} 🧑🏽‍💻 is nice", now: 0.24)
    stream.update("Café 🧑🏽‍💻 is lovely.", final: true, now: 0.7)
    #expect(stream.text.utf16.elementsEqual("Cafe\u{301} 🧑🏽‍💻 is lovely.".utf16))
}

@Test func rapidChunksPreserveWholeGraphemesAndAccelerateLongQueues() {
    #expect(LiveTextDelivery.nextChunk(in: "e\u{301} 🧑🏽‍💻") == "e\u{301} 🧑🏽‍💻")
    #expect(LiveTextDelivery.nextChunk(in: "🧑🏽‍💻 more") == "🧑🏽‍💻 mo")
    #expect(LiveTextDelivery.nextChunk(in: String(repeating: "a", count: 24)) == "aaaa")
    #expect(LiveTextDelivery.nextChunk(in: String(repeating: "a", count: 25)) == "aaaaaaaa")
    #expect(LiveTextDelivery.nextChunk(in: String(repeating: "a", count: 81)) == "aaaaaaaaaaaaaaaa")
    #expect(LiveTextDelivery.nextChunk(in: "") == "")
}

@Test func completedPhrasesBypassTheDelayWhileTheNextPhraseStaysBuffered() {
    var stream = StableText()
    stream.update("Hello. Next word", confirmedWordCount: 1, now: 0)
    #expect(stream.text == "Hello.")
    stream.update("Hello. Next phrase.", confirmedWordCount: 3, now: 0.1)
    #expect(stream.text == "Hello. Next phrase.")
}

@Test func contextAllowsAFirstResponseWithinTwoRecognitionPolls() {
    var stream = StableText()
    stream.update("Hello world", now: 0)
    stream.update("Hello world", now: 0.12)
    #expect(stream.text == "")
    stream.update("Hello world", now: 0.24)
    #expect(stream.text == "Hello")
}

@Test func aStableSingleWordAppearsWithoutWaitingForReleaseAndKeepsFinalPunctuation() {
    var stream = StableText()
    stream.update("Hello", now: 0)
    stream.update("Hello", now: 0.24)
    #expect(stream.text == "")
    stream.update("Hello", now: 0.36)
    #expect(stream.text == "Hello")
    stream.update("Hello.", final: true, now: 0.4)
    #expect(stream.text == "Hello.")
    stream.update("Hello.", final: true, now: 0.5)
    #expect(stream.text == "Hello.")
    stream.update("Hello!", final: true, now: 0.6)
    #expect(stream.text == "Hello.")
}

@Test func punctuationArrivingWithMoreSpeechAppendsBeforeTheNewWordsExactlyOnce() {
    var stream = StableText()
    stream.update("Hello", now: 0)
    stream.update("Hello", now: 0.36)
    stream.update("Hello, world", now: 0.48)
    #expect(stream.text == "Hello,")
    stream.update("Hello, world.", final: true, now: 0.5)
    #expect(stream.text == "Hello, world.")
}

@Test func theUncertainLastWordOfALongerPhraseWaitsForContextOrCompletion() {
    var stream = StableText()
    stream.update("This is a local speech record", now: 0)
    stream.update("This is a local speech record", now: 0.24)
    #expect(stream.text == "This is a local speech")
    stream.update("This is a local speech record", now: 0.96)
    #expect(stream.text == "This is a local speech")
    stream.update("This is a local speech recognition test.", final: true, now: 1)
    #expect(stream.text == "This is a local speech recognition test.")
}
