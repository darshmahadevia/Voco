@MainActor enum PermissionFixture {
    static var trusted = false
    static var monitorStarts = false
    static var prompts = 0
    static var settingsURLs: [URL] = []
    static var monitorStops = 0
}

@MainActor @discardableResult
func AXIsProcessTrustedWithOptions(_ options: CFDictionary?) -> Bool {
    PermissionFixture.prompts += 1
    return PermissionFixture.trusted
}

@MainActor func AXIsProcessTrusted() -> Bool { PermissionFixture.trusted }

@MainActor enum NSWorkspace {
    static let shared = Workspace()
    struct Application { let processIdentifier: pid_t }
    @MainActor final class Workspace {
        var frontmostApplication: Application?
        @discardableResult func open(_ url: URL) -> Bool {
            PermissionFixture.settingsURLs.append(url)
            return true
        }
        func activateFileViewerSelecting(_ urls: [URL]) {}
    }
}

@MainActor final class ShortcutMonitor {
    var key: TalkKey = .fn
    var onAction: ((HoldAction) -> Void)?
    var onEscape: (() -> Void)?
    var onContinuousToggle: (() -> Void)?
    var isRunning = false
    func start() -> Bool {
        isRunning = PermissionFixture.monitorStarts
        return isRunning
    }
    func stop() {
        PermissionFixture.monitorStops += 1
        isRunning = false
    }
}
