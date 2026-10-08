@main struct BaselinePermissionCheck {
    @MainActor static func main() {
        let model = AppModel()
        model.requestAccessibility()
        print("Permission prompts: \(PermissionFixture.prompts)")
        print("Concurrent Settings launches: \(PermissionFixture.settingsURLs.count)")
        if PermissionFixture.prompts != 1 || !PermissionFixture.settingsURLs.isEmpty { exit(1) }
    }
}
