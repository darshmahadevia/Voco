
@main @MainActor
struct PermissionCheck {
    static func main() {
        let model = AppModel()
        var returnedStates: [KeyboardAccessState] = []
        var restarts = 0
        model.returnToSettings = { returnedStates.append(model.keyboardAccessState) }
        model.restartApp = { restarts += 1 }
        precondition(model.keyboardAccessState == .required)
        model.requestAccessibility()
        precondition(model.keyboardAccessState == .waiting)
        precondition(PermissionFixture.prompts == 1)
        precondition(PermissionFixture.settingsURLs.isEmpty)
        model.refreshPermissions()
        precondition(model.keyboardAccessState == .waiting)
        model.requestAccessibility()
        precondition(PermissionFixture.prompts == 1)
        precondition(PermissionFixture.settingsURLs.count == 1)
        precondition(PermissionFixture.settingsURLs[0].absoluteString.hasSuffix("Privacy_Accessibility"))
        PermissionFixture.trusted = true
        model.refreshPermissions()
        precondition(model.keyboardAccessState == .restartNeeded)
        precondition(returnedStates == [.restartNeeded])
        model.requestAccessibility()
        precondition(restarts == 1)
        precondition(PermissionFixture.prompts == 1)
        PermissionFixture.monitorStarts = true
        model.refreshPermissions()
        precondition(model.keyboardAccessState == .ready)
        model.requestAccessibility()
        precondition(restarts == 1)
        precondition(returnedStates == [.restartNeeded])
        PermissionFixture.trusted = false
        model.refreshPermissions()
        precondition(model.keyboardAccessState == .required)
        precondition(!model.keyboardAllowed)
        precondition(PermissionFixture.monitorStops == 1)
        PermissionFixture.monitorStarts = false
        model.requestAccessibility()
        precondition(PermissionFixture.prompts == 2)
        PermissionFixture.trusted = true
        PermissionFixture.monitorStarts = true
        model.refreshPermissions()
        precondition(returnedStates == [.restartNeeded, .ready])
        model.refreshPermissions()
        precondition(returnedStates == [.restartNeeded, .ready])
        print("Permission flow passed: single prompt, Settings retry, granted-but-unavailable restart, ready, revocation, and reapproval.")
    }
}
