import AppKit
import Foundation

@MainActor
private final class NativeAppDelegate: NSObject, NSApplicationDelegate {
    let coordinator: NativeCoordinator

    init(modelDirectory: URL) {
        coordinator = NativeCoordinator(modelDirectory: modelDirectory)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        coordinator.start()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

@main
@MainActor
struct NativeApp {
    static func main() async {
        let arguments = Array(CommandLine.arguments.dropFirst())
        if NativeCLI.handles(arguments) {
            exit(await NativeCLI.run(arguments))
        }

        guard let modelPath = NativeCLI.value(after: "--model-directory", in: arguments) else {
            FileHandle.standardError.write(Data("Voco native: --model-directory PATH is required.\n".utf8))
            exit(64)
        }
        let application = NSApplication.shared
        application.setActivationPolicy(.accessory)
        let delegate = NativeAppDelegate(modelDirectory: URL(fileURLWithPath: modelPath))
        application.delegate = delegate
        withExtendedLifetime(delegate) { application.run() }
    }
}
