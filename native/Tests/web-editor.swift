import AppKit
import Foundation
import WebKit

@MainActor
final class WebEditorFixture {
    let window = NSWindow(contentRect: NSRect(x: 200, y: 200, width: 960, height: 700), styleMask: [.titled, .closable], backing: .buffered, defer: false)
    let browser = WKWebView(frame: NSRect(x: 0, y: 0, width: 960, height: 700))

    func evaluate(_ script: String) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            browser.evaluateJavaScript(script) { value, error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume(returning: value as? String ?? "") }
            }
        }
    }

    func run(helper: String, fixture: String) async throws {
        window.title = "Voco disposable WebKit browser editor"
        window.contentView = browser
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(browser)
        NSApp.activate(ignoringOtherApps: true)
        let url = URL(fileURLWithPath: fixture)
        browser.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        while browser.isLoading { try await Task.sleep(for: .milliseconds(20)) }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("voco-web-editor-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        for field in ["input", "textarea", "[contenteditable]"] {
            for selected in [false, true] {
                _ = try await evaluate("""
                (() => {
                  const field = document.querySelector('\(field)');
                  if ('value' in field) field.value = 'Before selected after';
                  else field.textContent = 'Before selected after';
                  field.focus();
                  const start = \(selected ? 7 : 15);
                  if ('setSelectionRange' in field) field.setSelectionRange(start, 15);
                  else {
                    const range = document.createRange();
                    range.setStart(field.firstChild, start); range.setEnd(field.firstChild, 15);
                    getSelection().removeAllRanges(); getSelection().addRange(range);
                  }
                  window.vocoEditorEvents.length = 0;
                  return 'ready';
                })()
                """)
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
                let speech = field == "textarea" && selected && environment["VOCO_VERIFY_AUDIO_FIXTURE"] != nil
                if speech, let audio = environment["VOCO_VERIFY_AUDIO_FIXTURE"], let model = environment["VOCO_VERIFY_MODEL_DIRECTORY"] {
                    process.arguments! += ["--audio-fixture", audio, "--model-directory", model]
                }
                try process.run()
                await withCheckedContinuation { continuation in
                    process.terminationHandler = { _ in continuation.resume() }
                }
                let report = try String(contentsOf: output, encoding: .utf8)
                let error = try String(contentsOf: errors, encoding: .utf8)
                let state = try await evaluate("""
                (() => {
                  const field = document.querySelector('\(field)');
                  const events = window.vocoEditorEvents.filter(event => event.field === field.getAttribute('aria-label'));
                  return JSON.stringify({value:field.value??field.textContent,lastInput:events.at(-1)?.value,inputCount:events.length});
                })()
                """)
                guard report.contains("Live insertion checks: PASS") else { throw NSError(domain: report + error + "\nEditor state: " + state, code: 1) }
                let parsed = try JSONSerialization.jsonObject(with: Data(state.utf8)) as? [String: Any]
                guard let count = parsed?["inputCount"] as? Int, count >= 6,
                      let value = parsed?["value"] as? String, value == parsed?["lastInput"] as? String
                else { throw NSError(domain: "WebKit application state differs from editor: " + state, code: 1) }
                if speech, let expected = environment["VOCO_VERIFY_EXPECTED_TRANSCRIPT"] {
                    guard value.contains(expected), report.contains("Verified Moonshine stream:") else { throw NSError(domain: "Missing expected streaming speech", code: 1) }
                }
                print("PASS WebKit browser \(field), selected=\(selected), input events=\(count), speech=\(speech)")
            }
        }
    }
}

@main
@MainActor
struct WebEditorCheck {
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        let fixture = WebEditorFixture()
        Task {
            do { try await fixture.run(helper: ProcessInfo.processInfo.environment["VOCO_VERIFY_DESKTOP_APP"] ?? CommandLine.arguments[1], fixture: CommandLine.arguments[2]); exit(0) }
            catch { FileHandle.standardError.write(Data("\(error)\n".utf8)); exit(1) }
        }
        withExtendedLifetime(fixture) { app.run() }
    }
}
