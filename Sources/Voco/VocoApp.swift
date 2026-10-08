import AppKit
import SwiftUI

@main
struct VocoApp {
    @MainActor static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let delegate = AppDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let model = AppModel()
    private var statusItem: NSStatusItem?
    private var pill: PillPanel?
    private var setupWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        pill = PillPanel(model: model)
        model.showPill = { [weak self] in self?.pill?.show() }
        model.hidePill = { [weak self] in self?.pill?.orderOut(nil) }
        model.returnToSettings = { [weak self] in self?.showSetup() }
        model.restartApp = { [weak self] in self?.restart() }
        model.setupSizeChanged = { [weak self] size in self?.setupWindow?.setContentSize(size) }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "waveform", accessibilityDescription: "Voco")
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        statusItem = item
        menuNeedsUpdate(menu)
        if CommandLine.arguments.contains("--verify-insertion") {
            var fixture: URL?
            if let index = CommandLine.arguments.firstIndex(of: "--audio-fixture"), index + 1 < CommandLine.arguments.count {
                fixture = URL(fileURLWithPath: CommandLine.arguments[index + 1])
            }
            Task {
                do {
                    try await verifyInsertion(audioFixture: fixture)
                    NSApp.terminate(nil)
                } catch {
                    print("Insertion verification failed: \(error.localizedDescription)")
                    exit(1)
                }
            }
            return
        }
        if CommandLine.arguments.contains("--check-shortcut") {
            print("Accessibility: \(model.accessibilityAllowed ? "granted" : "required")")
            print("Global shortcut: \(model.keyboardAllowed ? "available" : "unavailable")")
            print("Keyboard access: \(model.keyboardAccessState.rawValue)")
            exit(model.keyboardAllowed ? 0 : 2)
        }
        if CommandLine.arguments.contains("--render-previews") {
            renderPreviews()
            NSApp.terminate(nil)
            return
        }
        if CommandLine.arguments.contains("--measure-ui") {
            measureUI()
            NSApp.terminate(nil)
            return
        }
        if let index = CommandLine.arguments.firstIndex(of: "--verify-pauses"), index + 1 < CommandLine.arguments.count {
            setbuf(stdout, nil)
            Task {
                try? await Task.sleep(for: .seconds(25))
                print("Pause verification timed out")
                exit(1)
            }
            let url = URL(fileURLWithPath: CommandLine.arguments[index + 1])
            Task {
                do {
                    try await SpeechSession.verifyPauses(url)
                    NSApp.terminate(nil)
                } catch {
                    print("Pause verification failed: \(error.localizedDescription)")
                    exit(1)
                }
            }
            return
        }
        if let index = CommandLine.arguments.firstIndex(where: { $0 == "--transcribe-file" || $0 == "--transcribe-stream" }),
           index + 1 < CommandLine.arguments.count {
            let url = URL(fileURLWithPath: CommandLine.arguments[index + 1])
            Task {
                do {
                    let start = ContinuousClock.now
                    let text = CommandLine.arguments[index] == "--transcribe-stream"
                        ? try await SpeechSession.transcribeStream(url)
                        : try await SpeechSession.transcribeFile(url)
                    print("Transcript: \(text)")
                    print("Elapsed: \(start.duration(to: .now))")
                    NSApp.terminate(nil)
                } catch {
                    print("Transcription failed: \(error.localizedDescription)")
                    exit(1)
                }
            }
            return
        }
        if CommandLine.arguments.contains("--verify-restart") {
            setbuf(stdout, nil)
            print("Restarting Voco process \(getpid())")
            restart()
            return
        }
        showSetup()
        if CommandLine.arguments.contains("--request-keyboard-access") { model.requestAccessibility() }
        if model.microphoneAllowed { model.prepare() }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let state = NSMenuItem(title: model.isReady ? model.triggerHint : "Finish setup to start", action: nil, keyEquivalent: "")
        state.isEnabled = false
        menu.addItem(state)
        menu.addItem(.separator())
        menu.addItem(withTitle: "Settings…", action: #selector(showSetup), keyEquivalent: ",").target = self
        let copy = menu.addItem(withTitle: "Copy last transcript", action: #selector(copyLast), keyEquivalent: "")
        copy.target = self
        copy.isEnabled = model.keepLastTranscript && !model.lastTranscript.isEmpty
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Voco", action: #selector(quit), keyEquivalent: "q").target = self
    }

    @objc private func showSetup() {
        if setupWindow == nil {
            let host = NSHostingView(rootView: SetupView(model: model))
            let size = host.fittingSize
            let window = NSWindow(
                contentRect: NSRect(origin: .zero, size: size),
                styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false
            )
            window.title = "Voco"
            window.contentView = host
            window.isReleasedWhenClosed = false
            window.hidesOnDeactivate = false
            window.center()
            setupWindow = window
        }
        setupWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func copyLast() { model.copyLastTranscript() }
    @objc private func quit() { model.cancel(); NSApp.terminate(nil) }

    func applicationWillTerminate(_ notification: Notification) { model.cancel() }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSetup()
        return true
    }

    private func restart() {
        model.cancel()
        let launcher = Process()
        launcher.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        launcher.arguments = ["-n", Bundle.main.bundleURL.path]
        do {
            try launcher.run()
            launcher.waitUntilExit()
            guard launcher.terminationStatus == 0 else { throw CocoaError(.executableLoad) }
            NSApp.terminate(nil)
        } catch {
            let alert = NSAlert()
            alert.messageText = "Voco could not restart"
            alert.informativeText = "Quit Voco and reopen it from Applications. \(error.localizedDescription)"
            alert.runModal()
        }
    }

    private func renderPreviews() {
        let directory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(".impeccable/review")
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try render(SetupView(model: model), to: directory.appendingPathComponent("setup.png"))
            model.accessibilityAllowed = true
            model.keyboardAllowed = false
            try render(SetupView(model: model), to: directory.appendingPathComponent("setup-restart.png"))
            model.keyboardAllowed = true
            try render(SetupView(model: model), to: directory.appendingPathComponent("setup-ready.png"))
            model.phase = .listening
            model.transcript = "This is a preview of the live transcript. Your words appear here as you speak."
            try render(PillView(model: model), to: directory.appendingPathComponent("pill.png"))
            model.continuousListening = true
            try render(PillView(model: model), to: directory.appendingPathComponent("continuous.png"))
            model.continuousListening = false
            model.phase = .recovery(InsertionError.focusChanged.localizedDescription)
            try render(PillView(model: model), to: directory.appendingPathComponent("recovery.png"))
            print("Rendered setup, pill, and recovery previews to \(directory.path)")
        } catch {
            fputs("Preview rendering failed: \(error.localizedDescription)\n", stderr)
        }
    }

    private func measureUI() {
        model.phase = .listening
        let host = NSHostingView(rootView: PillView(model: model))
        host.frame = NSRect(x: 0, y: 0, width: 528, height: 260)
        let window = NSWindow(contentRect: host.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        var timings: [Double] = []
        for index in 1...20 {
            let start = ContinuousClock.now
            model.transcript = Array(repeating: "Live words", count: index).joined(separator: " ")
            host.layoutSubtreeIfNeeded()
            if let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
                host.cacheDisplay(in: host.bounds, to: bitmap)
            }
            let elapsed = start.duration(to: .now).components
            timings.append(Double(elapsed.seconds) * 1_000 + Double(elapsed.attoseconds) / 1e15)
        }
        timings.sort()
        print("Native pill update and render: median \(timings[10]) ms; p95 \(timings[18]) ms")
        window.close()
    }

    private func render<Content: View>(_ content: Content, to url: URL) throws {
        let host = NSHostingView(rootView: content)
        let size = host.fittingSize
        host.frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: host.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { throw CocoaError(.fileWriteUnknown) }
        host.cacheDisplay(in: host.bounds, to: bitmap)
        guard let data = bitmap.representation(using: .png, properties: [:]) else { throw CocoaError(.fileWriteUnknown) }
        try data.write(to: url)
        window.close()
    }
}
