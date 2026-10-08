extension AppModel {
    func verifyQuickTapRetention() -> Bool {
        committedText = "First phrase."
        transcript = "Second phrase."
        cancel()
        guard lastTranscript == "First phrase. Second phrase." else { return false }
        isPreparing = true
        arm()
        release()
        print("Saved transcript after quick tap: \(lastTranscript)")
        return lastTranscript == "First phrase. Second phrase."
    }
}

@main struct RecoveryCheck {
    @MainActor static func main() {
        _ = NSApplication.shared
        let saved = UserDefaults.standard.object(forKey: "keepLastTranscript")
        defer {
            if let saved { UserDefaults.standard.set(saved, forKey: "keepLastTranscript") }
            else { UserDefaults.standard.removeObject(forKey: "keepLastTranscript") }
        }
        let model = AppModel()
        model.keepLastTranscript = true
        guard model.verifyQuickTapRetention() else {
            print("Quick-tap retention: FAIL")
            exit(1)
        }
        print("Quick-tap retention: PASS")
    }
}
