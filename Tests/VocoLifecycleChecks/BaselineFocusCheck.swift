@main struct BaselineFocusCheck {
    @MainActor static func main() {
        FocusFixture.reset()
        let found = FocusTarget.capture()?.element.map { CFEqual($0, FocusFixture.field) } ?? false
        print("Electron cursor with initially inactive accessibility: \(found ? "FOUND" : "MISSING")")
        if !found { exit(1) }
    }
}
