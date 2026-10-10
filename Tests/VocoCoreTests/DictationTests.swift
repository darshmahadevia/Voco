import Testing
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
