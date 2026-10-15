import AppKit
import ApplicationServices
import AVFoundation

@main @MainActor
struct LiveDictationCheck {
    static func post(_ type: CGEventType, key: CGKeyCode, flags: CGEventFlags = []) {
        let event = CGEvent(keyboardEventSource: nil, virtualKey: key, keyDown: type != .keyUp)!
        event.type = type
        event.flags = flags
        event.post(tap: .cghidEventTap)
    }

    static func chord() {
        post(.flagsChanged, key: 63, flags: .maskSecondaryFn)
        post(.keyDown, key: 49, flags: .maskSecondaryFn)
        post(.keyUp, key: 49, flags: .maskSecondaryFn)
        post(.flagsChanged, key: 63)
    }

    static func words(_ text: String) -> [String] {
        text.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init)
    }

    static func check(window: NSWindow, editor: NSTextView) async throws {
        guard CommandLine.arguments.count == 3 else {
            throw NSError(domain: "Pass an audio fixture and its literal expected transcript.", code: 1)
        }
        guard AXIsProcessTrusted(), CGPreflightPostEventAccess() else {
            throw NSError(domain: "The launching terminal needs Accessibility access to post shortcut events.", code: 1)
        }
        var completed = false
        defer {
            post(.keyUp, key: 49)
            post(.flagsChanged, key: 63)
            if !completed {
                post(.keyDown, key: 53)
                post(.keyUp, key: 53)
            }
        }
        let expected = words(CommandLine.arguments[2])
        guard !expected.isEmpty else { throw NSError(domain: "Expected speech must contain words.", code: 1) }
        for continuous in [false, true] {
            editor.string = ""
            editor.setSelectedRange(NSRange(location: 0, length: 0))
            window.makeKeyAndOrderFront(nil)
            window.makeFirstResponder(editor)
            NSApp.activate(ignoringOtherApps: true)
            try await Task.sleep(for: .milliseconds(800))
            guard NSWorkspace.shared.frontmostApplication?.processIdentifier == ProcessInfo.processInfo.processIdentifier else {
                throw NSError(domain: "The disposable editor must stay focused during verification.", code: 1)
            }
            let player = try AVAudioPlayer(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
            player.prepareToPlay()
            if continuous { chord() }
            else { post(.flagsChanged, key: 63, flags: .maskSecondaryFn) }
            try await Task.sleep(for: .milliseconds(800))
            guard player.play() else { throw NSError(domain: "Speech fixture playback failed.", code: 1) }
            while player.isPlaying { try await Task.sleep(for: .milliseconds(100)) }
            try await Task.sleep(for: .milliseconds(500))
            if continuous { chord() }
            else { post(.flagsChanged, key: 63) }
            let deadline = ContinuousClock.now + .seconds(30)
            while editor.string.isEmpty, ContinuousClock.now < deadline {
                try await Task.sleep(for: .milliseconds(100))
            }
            guard words(editor.string) == expected else {
                throw NSError(domain: "Dictation did not insert the complete expected speech. Check app readiness, speaker volume, and microphone input. Actual: \(editor.string.debugDescription)", code: 1)
            }
            print("PASS installed dictation: \(continuous ? "Fn+Space" : "Fn hold/release"), acoustic capture, local recognition, complete editor insertion")
        }
        completed = true
    }

    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        let window = NSWindow(contentRect: NSRect(x: 200, y: 200, width: 700, height: 420), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        let editor = NSTextView(frame: NSRect(x: 0, y: 0, width: 700, height: 420))
        window.title = "Voco disposable dictation check"
        editor.isRichText = false
        window.contentView = editor
        Task {
            do { try await check(window: window, editor: editor); exit(0) }
            catch { FileHandle.standardError.write(Data("\(error)\n".utf8)); exit(1) }
        }
        withExtendedLifetime(window) { app.run() }
    }
}
