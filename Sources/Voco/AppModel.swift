import AppKit
@preconcurrency import ApplicationServices
import AVFoundation
import Observation
import VocoCore
import OSLog

enum KeyboardAccessState: String {
    case required, waiting, ready, restartNeeded

    var button: String {
        switch self {
        case .required: "Allow"
        case .waiting: "Open Settings"
        case .ready: "Allowed"
        case .restartNeeded: "Restart Voco"
        }
    }

    var detail: String {
        switch self {
        case .required: "Allow Voco to use your talk key and insert your words."
        case .waiting: "Enable Voco in macOS settings, then return here."
        case .ready: "Your talk key and text insertion are available."
        case .restartNeeded: "Access is granted. Restart Voco to start the keyboard shortcut."
        }
    }
}

enum DictationPhase: Equatable {
    case idle, starting, listening, finishing, recovery(String)
    var title: String {
        switch self {
        case .idle: "Ready when you are"
        case .starting: "Opening microphone"
        case .listening: "Listening"
        case .finishing: "Finishing up"
        case .recovery: "Your words are saved here"
        }
    }
}

@Observable @MainActor
final class AppModel {
    private static let defaults: UserDefaults = {
        let defaults = UserDefaults.standard
        if Bundle.main.bundleIdentifier == "org.vocoapp.Voco",
           !defaults.bool(forKey: "migratedUtterPreferences") {
            let legacy = UserDefaults(suiteName: "org.utterapp.Utter")
            for key in ["talkKey", "pauseSeconds", "keepLastTranscript"] {
                if defaults.object(forKey: key) == nil, let value = legacy?.object(forKey: key) {
                    defaults.set(value, forKey: key)
                }
            }
            defaults.set(true, forKey: "migratedUtterPreferences")
        }
        return defaults
    }()
    var phase: DictationPhase = .idle
    var transcript = ""
    var lastTranscript = ""
    var continuousListening = false
    var liveTypingAvailable = true
    var pauseSeconds = AppModel.defaults.object(forKey: "pauseSeconds") as? Double ?? 1.5 {
        didSet { AppModel.defaults.set(pauseSeconds, forKey: "pauseSeconds") }
    }
    var triggerHint: String { "Hold \(shortcut.label) or press Fn + Space." }
    var keepLastTranscript = AppModel.defaults.object(forKey: "keepLastTranscript") as? Bool ?? true {
        didSet {
            AppModel.defaults.set(keepLastTranscript, forKey: "keepLastTranscript")
            if !keepLastTranscript { lastTranscript = "" }
        }
    }
    private let logger = Logger(subsystem: "org.vocoapp.Voco", category: "Dictation")
    @ObservationIgnored private var firstPreviewUpdateAt: ContinuousClock.Instant?
    var setupMessage = "Prepare English transcription to get started."
    var downloadProgress: Double?
    var isPreparing = false
    var microphoneAllowed = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    var keyboardAllowed = false
    var accessibilityAllowed = AXIsProcessTrusted()
    var shortcut: TalkKey {
        didSet {
            cancel()
            monitor.stop()
            monitor.key = shortcut
            AppModel.defaults.set(shortcut.rawValue, forKey: "talkKey")
            refreshPermissions()
        }
    }
    var showPill: (() -> Void)?
    var hidePill: (() -> Void)?
    var returnToSettings: (() -> Void)?
    var restartApp: (() -> Void)?
    var pillSizeChanged: ((CGSize) -> Void)?
    var setupSizeChanged: ((CGSize) -> Void)?
    private let monitor = ShortcutMonitor()
    private var prepared: SpeechSession?
    private var active: SpeechSession?
    private var target: FocusTarget?
    private var sessionID = UUID()
    private var holdTask: Task<Void, Never>?
    private var finishTask: Task<Void, Never>?
    private var timeoutTask: Task<Void, Never>?
    private var prepareTask: Task<Void, Never>?
    private var permissionTimer: Timer?
    private var waitingForKeyboardPermission = false
    private var pauseTask: Task<Void, Never>?
    private var commitTask: Task<Void, Never>?
    private var stopAfterCommit = false
    private var pauseGate = PauseGate()
    private var committedThrough = -1.0
    private var committedText = ""
    private var liveWriter: LiveTextWriter?
    private var liveUpdateTask: Task<Void, Never>?

    var isReady: Bool { prepared != nil && keyboardAllowed && microphoneAllowed && accessibilityAllowed }
    var speechReady: Bool { prepared != nil }
    var keyboardAccessState: KeyboardAccessState {
        if accessibilityAllowed { return keyboardAllowed ? .ready : .restartNeeded }
        return waitingForKeyboardPermission ? .waiting : .required
    }
    var keyboardPermissionName: String {
        if #available(macOS 27, *) { return "Device Control and Data Access" }
        return "Accessibility"
    }

    init() {
        shortcut = TalkKey(rawValue: AppModel.defaults.string(forKey: "talkKey") ?? "") ?? .fn
        monitor.key = shortcut
        monitor.onAction = { [weak self] action in
            switch action {
            case .pressed: self?.press()
            case .released: self?.release()
            case .cancelled: self?.cancel()
            }
        }
        monitor.onEscape = { [weak self] in self?.cancel() }
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshPermissions() }
        }
        refreshPermissions()
    }

    func refreshPermissions() {
        microphoneAllowed = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        accessibilityAllowed = AXIsProcessTrusted()
        if accessibilityAllowed {
            keyboardAllowed = monitor.start()
        } else {
            keyboardAllowed = false
            if monitor.isRunning {
                monitor.stop()
                cancel()
            }
        }
        if accessibilityAllowed && waitingForKeyboardPermission {
            waitingForKeyboardPermission = false
            returnToSettings?()
        }
    }

    func requestAccessibility() {
        refreshPermissions()
        switch keyboardAccessState {
        case .required:
            waitingForKeyboardPermission = true
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
            refreshPermissions()
        case .waiting:
            openPrivacy("Accessibility")
        case .restartNeeded:
            restartApp?()
        case .ready:
            break
        }
    }

    func revealApp() {
        NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
    }

    func openPrivacy(_ pane: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_\(pane)") {
            NSWorkspace.shared.open(url)
        }
    }

    func prepare() {
        guard prepareTask == nil, prepared == nil else { return }
        isPreparing = true
        setupMessage = "Preparing English transcription…"
        prepareTask = Task { [self] in
            defer { isPreparing = false; prepareTask = nil; downloadProgress = nil }
            do {
                if AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined {
                    microphoneAllowed = await AVCaptureDevice.requestAccess(for: .audio)
                    returnToSettings?()
                }
                guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized else {
                    throw VocoError.microphone
                }
                prepared = try await SpeechSession.prepare { [weak self] progress in
                    self?.downloadProgress = progress
                    self?.setupMessage = progress == nil ? "Warming up transcription…" : "Downloading the English speech model…"
                }
                setupMessage = "English is ready. Speech stays on your Mac."
                refreshPermissions()
            } catch {
                setupMessage = error.localizedDescription
            }
        }
    }

    private func press() {
        guard !continuousListening else { return }
        arm()
    }

    private func toggleContinuous() {
        if continuousListening { stopCapture(); return }
        guard microphoneAllowed, keyboardAllowed, accessibilityAllowed else {
            returnToSettings?()
            return
        }
        let focus = FocusTarget.capture()
        cancel()
        prepare()
        sessionID = UUID()
        let id = sessionID
        target = focus
        holdTask = Task { await startCapture(id: id, continuous: true) }
    }

    private func arm() {
        guard active == nil, holdTask == nil, phase != .finishing else { return }
        guard prepared != nil || isPreparing else { return }
        sessionID = UUID()
        let id = sessionID
        target = FocusTarget.capture()
        holdTask = Task { [self] in
            do { try await Task.sleep(for: .milliseconds(140)) } catch { return }
            guard id == sessionID else { return }
            await startCapture(id: id, continuous: false)
        }
    }

    private func startCapture(id: UUID, continuous: Bool) async {
        guard id == sessionID else { return }
        committedThrough = -1
        committedText = ""
        pauseGate = PauseGate()
        continuousListening = continuous
        phase = .starting
        transcript = ""
        showPill?()
        if prepared == nil { await prepareTask?.value }
        guard !Task.isCancelled, id == sessionID else { return }
        guard let session = prepared else {
            fail(setupMessage, id: id)
            return
        }
        do {
            guard let target else { throw InsertionError.focusChanged }
            let resolvedTarget = try await target.resolved()
            guard !Task.isCancelled, id == sessionID else { return }
            self.target = resolvedTarget
            holdTask = nil
            prepared = nil
            active = session
            do {
                liveWriter = try LiveTextWriter(target: resolvedTarget)
                liveTypingAvailable = true
            } catch InsertionError.liveUnsupported {
                liveWriter = nil
                liveTypingAvailable = false
            }
            try session.start(onUpdate: { [weak self] update in
                guard let self, self.sessionID == id else { return }
                let text = update.text(after: self.committedThrough)
                if self.transcript.isEmpty && !text.isEmpty { self.firstPreviewUpdateAt = .now }
                if text != self.transcript && !text.isEmpty {
                    self.pauseGate.receivedText(at: ProcessInfo.processInfo.systemUptime)
                }
                self.transcript = text
                self.scheduleLiveUpdate(id: id)
            }, onSpeechActivity: { [weak self] in
                Task { @MainActor in
                    guard let self, self.sessionID == id else { return }
                    self.pauseGate.heardSpeech(at: ProcessInfo.processInfo.systemUptime)
                }
            }, onFailure: { [weak self] message in
                self?.fail(message, id: id)
            })
            phase = .listening
            if continuous {
                pauseTask = Task { [self] in
                    while !Task.isCancelled {
                        do { try await Task.sleep(for: .milliseconds(200)) } catch { return }
                        guard id == sessionID else { return }
                        if phase == .listening, commitTask == nil,
                           pauseGate.shouldInsert(at: ProcessInfo.processInfo.systemUptime, pause: pauseSeconds) {
                            commitPause(id: id)
                        }
                    }
                }
            }
        } catch { fail(error.localizedDescription, id: id) }
    }

    private func release() {
        guard !continuousListening else { return }
        if holdTask != nil { cancel(); return }
        stopCapture()
    }

    private func commitPause(id: UUID) {
        guard let session = active else { return }
        timeoutTask = Task {
            do { try await Task.sleep(for: .seconds(8)) } catch { return }
            fail(VocoError.timedOut.localizedDescription, id: id)
        }
        commitTask = Task {
            do {
                let snapshot = try await session.finalizePause()
                guard id == sessionID else { return }
                let current = session.currentTranscript
                if try updateLiveText(liveText(current.text(after: committedThrough))), let liveWriter {
                    liveUpdateTask?.cancel()
                    liveUpdateTask = nil
                    if !current.hasProvisionalText {
                        let batch = current.finalized(after: committedThrough)
                        if !batch.text.isEmpty {
                            committedText += liveText(batch.text)
                            committedThrough = batch.end
                            try liveWriter.commit()
                            transcript = ""
                            rememberTranscript()
                        }
                        pauseGate.inserted()
                    } else { pauseGate.heardSpeech(at: ProcessInfo.processInfo.systemUptime) }
                } else {
                    try await insertPending(snapshot, id: id)
                }
                guard id == sessionID else { return }
                timeoutTask?.cancel()
                timeoutTask = nil
                commitTask = nil
                if stopAfterCommit { stopAfterCommit = false; stopCapture() }
            } catch {
                guard id == sessionID else { return }
                fail(error.localizedDescription, id: id)
            }
        }
    }

    private func insertPending(_ snapshot: Transcript, id: UUID) async throws {
        let batch = snapshot.finalized(after: committedThrough)
        guard !batch.text.isEmpty else {
            pauseGate.heardSpeech(at: ProcessInfo.processInfo.systemUptime)
            return
        }
        guard let target else { throw InsertionError.focusChanged }
        let separator = !committedText.isEmpty && !".,!?;:)".contains(batch.text.first!) ? " " : ""
        if try !updateLiveText(separator + batch.text) { try await target.insert(separator + batch.text) }
        guard id == sessionID else { return }
        committedThrough = batch.end
        committedText += separator + batch.text
        transcript = (active?.currentTranscript ?? snapshot).text(after: committedThrough)
        pauseGate.inserted()
        if !transcript.isEmpty { pauseGate.receivedText(at: ProcessInfo.processInfo.systemUptime) }
        rememberTranscript()
    }

    private func stopCapture() {
        guard finishTask == nil else { return }
        liveUpdateTask?.cancel()
        liveUpdateTask = nil
        pauseTask?.cancel()
        pauseTask = nil
        if commitTask != nil {
            stopAfterCommit = true
            phase = .finishing
            return
        }
        if holdTask != nil { cancel(); return }
        guard let session = active else { return }
        phase = .finishing
        let id = sessionID
        timeoutTask = Task {
            do { try await Task.sleep(for: .seconds(8)) } catch { return }
            fail(VocoError.timedOut.localizedDescription, id: id)
        }
        finishTask = Task {
            do {
                let snapshot = try await session.finishTranscript()
                guard id == sessionID else { return }
                timeoutTask?.cancel()
                timeoutTask = nil
                if snapshot.finalized(after: committedThrough).text.isEmpty && !transcript.isEmpty {
                    fail("The speech engine did not finalize your words. Copy the preview below.", id: id)
                    return
                }
                try await insertPending(snapshot, id: id)
                guard id == sessionID else { return }
                complete()
            } catch {
                guard id == sessionID else { return }
                fail(error.localizedDescription, id: id)
            }
        }
    }

    func stopListening() { stopCapture() }

    private func complete() {
        liveWriter = nil
        continuousListening = false
        active = nil
        target = nil
        finishTask = nil
        phase = .idle
        hidePill?()
        prepare()
    }

    private func fail(_ message: String, id: UUID) {
        guard id == sessionID else { return }
        rememberTranscript()
        logger.error("Recovery: \(message, privacy: .public)")
        let session = active
        sessionID = UUID()
        liveUpdateTask?.cancel()
        liveUpdateTask = nil
        liveWriter = nil
        continuousListening = false
        pauseTask?.cancel()
        commitTask?.cancel()
        pauseTask = nil
        commitTask = nil
        stopAfterCommit = false
        holdTask?.cancel()
        finishTask?.cancel()
        timeoutTask?.cancel()
        holdTask = nil
        finishTask = nil
        timeoutTask = nil
        active = nil
        target = nil
        phase = .recovery(message)
        showPill?()
        Task { await session?.cancel(); prepare() }
    }

    func cancel() {
        rememberTranscript()
        let session = active
        sessionID = UUID()
        liveUpdateTask?.cancel()
        liveUpdateTask = nil
        liveWriter = nil
        continuousListening = false
        pauseTask?.cancel()
        commitTask?.cancel()
        pauseTask = nil
        commitTask = nil
        stopAfterCommit = false
        holdTask?.cancel()
        finishTask?.cancel()
        timeoutTask?.cancel()
        holdTask = nil
        finishTask = nil
        timeoutTask = nil
        active = nil
        target = nil
        phase = .idle
        hidePill?()
        if let session { Task { await session.cancel(); prepare() } }
    }

    func copyTranscript() {
        guard !transcript.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(transcript, forType: .string)
        cancel()
    }

    private func rememberTranscript() {
        let separator = !committedText.isEmpty && !transcript.isEmpty ? " " : ""
        let text = committedText + separator + transcript
        if keepLastTranscript && !text.isEmpty { lastTranscript = text }
    }

    private func liveText(_ text: String) -> String {
        guard !text.isEmpty else { return "" }
        return (!committedText.isEmpty && !".,!?;:)".contains(text.first!) ? " " : "") + text
    }

    private func scheduleLiveUpdate(id: UUID) {
        guard liveWriter != nil, liveUpdateTask == nil, phase == .listening else { return }
        liveUpdateTask = Task {
            do {
                try await Task.sleep(for: .milliseconds(25))
                guard id == sessionID, phase == .listening else { return }
                if try updateLiveText(liveText(transcript)) { noteLiveUpdate() }
                liveUpdateTask = nil
            } catch {
                guard !Task.isCancelled, id == sessionID else { return }
                fail(error.localizedDescription, id: id)
            }
        }
    }

    @discardableResult
    private func updateLiveText(_ text: String) throws -> Bool {
        guard let liveWriter else { return false }
        do {
            try liveWriter.update(text)
            return true
        } catch InsertionError.liveUnsupported {
            self.liveWriter = nil
            liveTypingAvailable = false
            return false
        }
    }

    private func noteLiveUpdate() {
        guard let firstPreviewUpdateAt else { return }
        logger.notice("First result to live text insertion: \(String(describing: firstPreviewUpdateAt.duration(to: .now)), privacy: .public)")
        self.firstPreviewUpdateAt = nil
    }

    func copyLastTranscript() {
        guard !lastTranscript.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(lastTranscript, forType: .string)
    }
}
