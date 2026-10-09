import AppKit
import Foundation

@MainActor
final class NativeEditorFixture {
    let window = NSWindow(contentRect: NSRect(x: 200, y: 200, width: 700, height: 420), styleMask: [.titled, .closable], backing: .buffered, defer: false)
    let editor = NSTextView(frame: NSRect(x: 0, y: 0, width: 700, height: 420))

    func run(helper: String) async throws {
        window.title = "Voco disposable native editor"
        editor.isRichText = false
        window.contentView = editor
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(editor)
        NSApp.activate(ignoringOtherApps: true)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("voco-native-editor-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        for selected in [false, true] {
            editor.string = "Before selected after"
            editor.setSelectedRange(NSRange(location: selected ? 7 : 15, length: selected ? 8 : 0))
            let output = directory.appendingPathComponent("output.log")
            let errors = directory.appendingPathComponent("error.log")
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            process.environment = ProcessInfo.processInfo.environment.filter { $0.key != "ELECTRON_RUN_AS_NODE" }
            process.arguments = ["-W", "-g", "-n", helper, "--stdout", output.path, "--stderr", errors.path, "--args", "--verify-live-insertion", "Before selected after"]
            let environment = ProcessInfo.processInfo.environment
            if environment["VOCO_VERIFY_DESKTOP_APP"] != nil {
                process.arguments! += ["--verify-desktop", "--verification-directory=\(directory.path)"]
                if let model = environment["VOCO_VERIFY_MODEL_DIRECTORY"] {
                    process.arguments! += ["--verification-model-directory=\(model)"]
                }
            }
            if let audio = environment["VOCO_VERIFY_AUDIO_FIXTURE"], let model = environment["VOCO_VERIFY_MODEL_DIRECTORY"] {
                process.arguments! += ["--audio-fixture", audio, "--model-directory", model]
            }
            try process.run()
            await withCheckedContinuation { continuation in
                process.terminationHandler = { _ in continuation.resume() }
            }
            let report = try String(contentsOf: output, encoding: .utf8)
            let error = try String(contentsOf: errors, encoding: .utf8)
            guard report.contains("Live insertion checks: PASS") else { throw NSError(domain: report + error, code: 1) }
            let speech = environment["VOCO_VERIFY_AUDIO_FIXTURE"] == nil ? "" : " " + (environment["VOCO_VERIFY_EXPECTED_TRANSCRIPT"] ?? "")
            let expected = "Before selected " + String(repeating: "Long 🍦 phrase. ", count: 8) + " Next phrase." + speech + " after"
            guard editor.string == expected, editor.selectedRange() == NSRange(location: 0, length: 0) else { throw NSError(domain: "Native editor state differs from expected", code: 1) }
            print("PASS AppKit NSTextView, selected=\(selected), speech=\(!speech.isEmpty)")
        }
    }
}

@main
@MainActor
struct NativeEditorCheck {
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        let fixture = NativeEditorFixture()
        let helper = ProcessInfo.processInfo.environment["VOCO_VERIFY_DESKTOP_APP"] ?? CommandLine.arguments[1]
        Task {
            do { try await fixture.run(helper: helper); exit(0) }
            catch { FileHandle.standardError.write(Data("\(error)\n".utf8)); exit(1) }
        }
        withExtendedLifetime(fixture) { app.run() }
    }
}
