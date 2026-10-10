import Testing
@testable import VocoCore

@Test func spaceChordPromotesHoldAndIgnoresRepeatsAndFnRelease() {
    var gesture = HoldGesture()
    #expect(gesture.update(triggerDown: true) == .pressed)
    #expect(gesture.update(triggerDown: true, keyPressed: true, spacePressed: true) == .toggleContinuous)
    #expect(gesture.update(triggerDown: true, keyPressed: true, spacePressed: true, isRepeat: true) == nil)
    #expect(gesture.update(triggerDown: false) == nil)
    #expect(gesture.update(triggerDown: true, keyPressed: true, spacePressed: true, isRepeat: true) == nil)
    #expect(gesture.update(triggerDown: true, spaceReleased: true) == .pressed)
    #expect(gesture.update(triggerDown: true, keyPressed: true, spacePressed: true) == .toggleContinuous)
}

@Test func blockedCombinationRequiresFnReleaseBeforeSpaceChord() {
    var gesture = HoldGesture()
    #expect(gesture.update(triggerDown: true, otherModifier: true) == nil)
    #expect(gesture.update(triggerDown: true, keyPressed: true, spacePressed: true) == nil)
    #expect(gesture.update(triggerDown: false, spaceReleased: true) == nil)
    #expect(gesture.update(triggerDown: true, keyPressed: true, spacePressed: true) == .toggleContinuous)
}

@Test func unrelatedKeyCancelsHoldAndSpaceDoesNotRestartIt() {
    var gesture = HoldGesture()
    #expect(gesture.update(triggerDown: true) == .pressed)
    #expect(gesture.update(triggerDown: true, keyPressed: true) == .cancelled)
    #expect(gesture.update(triggerDown: true, keyPressed: true, spacePressed: true) == nil)
    #expect(gesture.update(triggerDown: false, spaceReleased: true) == nil)
    #expect(gesture.update(triggerDown: true) == .pressed)
}

@Test func spaceHeldBeforeFnCannotSuppressHoldRelease() {
    var gesture = HoldGesture()
    #expect(gesture.update(triggerDown: false, keyPressed: true, spacePressed: true) == nil)
    #expect(gesture.update(triggerDown: true) == .pressed)
    #expect(gesture.update(triggerDown: true, keyPressed: true, spacePressed: true, isRepeat: true) == nil)
    #expect(gesture.update(triggerDown: false) == .released)
}
