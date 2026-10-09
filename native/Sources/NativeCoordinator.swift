import AppKit
@preconcurrency import ApplicationServices
import AVFoundation
import Darwin
import Foundation
import VocoCore

@MainActor
final class NativeCoordinator {
    private final class Dictation {
        let id: UUID
        let stream: Int32
        let target: FocusTarget
        let bufferedWriter: BufferedTextWriter
        var ledger = TranscriptLedger()
        var liveWriter: LiveTextWriter?
        var pollTask: Task<Void, Never>?
        var commitTask: Task<Void, Never>?
        var updateTask: Task<Void, Never>?
        var polling = false
        var commitInFlight = false

        init(id: UUID, stream: Int32, target: FocusTarget, bufferedWriter: BufferedTextWriter, liveWriter: LiveTextWriter?) {
            self.id = id
            self.stream = stream
            self.target = target
            self.bufferedWriter = bufferedWriter
            self.liveWriter = liveWriter
        }

        var buffered: Bool { liveWriter == nil }
        var pendingLines: [MoonshineLine] { ledger.pendingLines }
        var pendingText: String { ledger.pendingText }
        var fullText: String { ledger.text }
    }

    private let state = NativeStateStore()
    private let engine = MoonshineEngine()
    private let audio = NativeAudioInput()
    private var lastLevelPublication = ContinuousClock.now
    private let modelDirectory: URL
    private let installer: ModelInstaller
    private let shortcutMonitor = ShortcutMonitor()
    private var downloadTask: Task<Void, Never>?
    private var downloadGeneration: UUID?
    private var holdTask: Task<Void, Never>?
    private var targetResolutionTask: Task<Void, Never>?
    private var startingSessionID: UUID?
    private var permissionTimer: Timer?
    private var active: Dictation?
    private var sessionGate = SessionIDGate()
    private var finishing = false
    private var outputLock = NSLock()

    init(modelDirectory: URL) {
        self.modelDirectory = modelDirectory.standardizedFileURL
        installer = ModelInstaller(modelDirectory: modelDirectory)
        shortcutMonitor.onAction = { [weak self] action in
            switch action {
            case .pressed: self?.armHold()
            case .released: self?.releaseHold()
            case .cancelled: self?.cancelDictation(message: "Dictation canceled. Your words are saved here.", clearRecovery: true)
            }
        }
        shortcutMonitor.onEscape = { [weak self] in
            self?.cancelDictation(message: "Dictation canceled. Your words are saved here.", clearRecovery: true)
        }
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshPermissions(publish: true) }
        }
    }

    func start() {
        refreshPermissions(publish: false)
        do {
            if try installer.verifyCachedModel() {
                state.model = .loading
                publishState()
                engine.warm(modelDirectory: modelDirectory) { [weak self] result in
                    guard let self else { return }
                    switch result {
                    case .success: self.state.model = .ready
                    case let .failure(error): self.state.model = .error(error.localizedDescription)
                    }
                    self.publishState()
                }
            } else {
                state.model = .missing
                publishState()
            }
        } catch {
            state.model = .error(error.localizedDescription)
            publishState()
        }
        readInput(onLine: { [weak self] line in self?.receive(line) }, onEnd: { [weak self] in
            self?.shutdown()
        })
    }

    func receive(_ line: String) {
        guard let data = line.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let id = object["id"] as? String, !id.isEmpty,
              let command = object["command"] as? [String: Any],
              let kind = command["kind"] as? String else {
            writeError("Ignored malformed command JSON.")
            return
        }

        do {
            try dispatch(kind: kind, command: command)
            writeMessage(["type": "reply", "id": id, "ok": true])
            publishState()
        } catch {
            writeMessage(["type": "reply", "id": id, "ok": false, "error": error.localizedDescription])
        }
    }

    private func dispatch(kind: String, command: [String: Any]) throws {
        switch kind {
        case "downloadModel": beginDownload()
        case "cancelDownload": cancelDownload()
        case "requestMicrophone": requestMicrophone()
        case "requestAccessibility": requestAccessibility()
        case "openPrivacy":
            guard let pane = command["pane"] as? String, ["microphone", "accessibility"].contains(pane) else {
                throw NativeError.invalidCommand("Choose the microphone or accessibility privacy setting.")
            }
            openPrivacy(pane)
        case "setPreferences": try setPreferences(command["preferences"])
        case "stop": stopDictation()
        case "cancel": cancelDictation(message: "Dictation canceled. Your words are saved here.", clearRecovery: true)
        case "copyRecovery": copyRecovery()
        case "copyLast": copyLastTranscript()
        case "refresh": refreshPermissions(publish: false)
        case "restart": NSApp.terminate(nil)
        default: throw NativeError.invalidCommand("Voco received an unknown command.")
        }
    }

    private func setPreferences(_ value: Any?) throws {
        guard let raw = value as? [String: Any],
              let keep = raw["keepLastTranscript"] as? Bool else {
            throw NativeError.invalidCommand("Voco received invalid preferences.")
        }
        state.preferences = NativePreferences(keepLastTranscript: keep)
        if !keep { state.lastTranscript = "" }
        refreshPermissions(publish: false)
    }

    private func beginDownload() {
        guard downloadTask == nil else { return }
        switch state.model {
        case .ready, .loading: return
        case .missing, .downloading, .error: break
        }
        let generation = UUID()
        downloadGeneration = generation
        state.model = .downloading(progress: 0, file: "Starting download…")
        publishState()
        let installer = self.installer
        downloadTask = Task { [weak self] in
            do {
                try await installer.download { [weak self] file, progress in
                    Task { @MainActor in
                        guard let self, self.downloadGeneration == generation else { return }
                        guard case .downloading = self.state.model else { return }
                        self.state.model = .downloading(progress: progress, file: file)
                        self.publishState()
                    }
                }
                guard let self, self.downloadGeneration == generation, !Task.isCancelled else { return }
                self.downloadTask = nil
                self.state.model = .loading
                self.publishState()
                self.engine.warm(modelDirectory: self.modelDirectory) { [weak self] result in
                    guard let self, self.downloadGeneration == generation else { return }
                    self.downloadGeneration = nil
                    switch result {
                    case .success: self.state.model = .ready
                    case let .failure(error): self.state.model = .error(error.localizedDescription)
                    }
                    self.publishState()
                }
            } catch is CancellationError {
                guard let self, self.downloadGeneration == generation else { return }
                self.downloadTask = nil
                self.downloadGeneration = nil
                self.state.model = .missing
                self.publishState()
            } catch {
                guard let self, self.downloadGeneration == generation else { return }
                self.downloadTask = nil
                self.downloadGeneration = nil
                self.state.model = .error(error.localizedDescription)
                self.publishState()
            }
        }
    }

    private func cancelDownload() {
        guard let downloadTask else { return }
        downloadGeneration = nil
        self.downloadTask = nil
        downloadTask.cancel()
        state.model = .missing
        publishState()
    }

    private func requestMicrophone() {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: break
        case .denied, .restricted: openPrivacy("microphone")
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] _ in
                Task { @MainActor in self?.refreshPermissions(publish: true) }
            }
        @unknown default: openPrivacy("microphone")
        }
        refreshPermissions(publish: false)
    }

    private func requestAccessibility() {
        if AXIsProcessTrusted() {
            refreshPermissions(publish: false)
            return
        }
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        openPrivacy("accessibility")
        refreshPermissions(publish: false)
    }

    private func openPrivacy(_ pane: String) {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_\(pane.capitalized)") else { return }
        NSWorkspace.shared.open(url)
    }

    private func refreshPermissions(publish: Bool) {
        state.microphone = PermissionSnapshot.microphoneStatus()
        state.accessibility = PermissionSnapshot.accessibilityAllowed
        state.shortcut = state.accessibility ? shortcutMonitor.start() : false
        if !state.accessibility {
            if shortcutMonitor.isRunning { shortcutMonitor.stop() }
            cancelDictation(message: "Accessibility access was turned off. Your words are saved here.")
        } else if state.microphone != "granted", active != nil || startingSessionID != nil {
            cancelDictation(message: "Microphone access was turned off. Your words are saved here.")
        }
        if publish { publishState() }
    }

    private func armHold() {
        guard active == nil, holdTask == nil, !finishing else { return }
        guard canDictate else { writeShowSettings(); return }
        guard let target = captureTarget() else { writeShowSettings(); return }
        let id = UUID()
        holdTask = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(140)) } catch { return }
            guard let self, self.holdTask != nil else { return }
            self.holdTask = nil
            self.startDictation(id: id, target: target)
        }
    }

    private func releaseHold() {
        holdTask?.cancel()
        holdTask = nil
        if active != nil {
            stopDictation()
        } else if startingSessionID != nil {
            cancelTargetResolution()
            state.session = .idle
            publishState()
        }
    }

    private var canDictate: Bool {
        if case .ready = state.model {
            return state.microphone == "granted" && state.accessibility && state.shortcut
        }
        return false
    }

    private func captureTarget() -> FocusTarget? {
        guard let target = FocusTarget.capture(),
              !FocusTargetPolicy.isParentProcess(target.processID, parentProcessID: getppid()) else { return nil }
        return target
    }

    private func startDictation(id: UUID, target: FocusTarget) {
        guard canDictate, active == nil, !finishing else { writeShowSettings(); return }
        sessionGate.begin(id)
        startingSessionID = id
        state.session = .starting
        publishState()

        targetResolutionTask = Task { [weak self] in
            do {
                let resolvedTarget = try await target.resolved()
                guard let self, self.startingSessionID == id, self.sessionGate.accepts(id) else { return }
                self.startingSessionID = nil
                self.targetResolutionTask = nil
                self.openDictation(id: id, target: resolvedTarget)
            } catch {
                guard let self, self.startingSessionID == id, self.sessionGate.accepts(id) else { return }
                self.startingSessionID = nil
                self.targetResolutionTask = nil
                self.sessionGate.invalidate()
                self.state.session = .recovery(message: error.localizedDescription, text: "")
                self.publishState()
            }
        }
    }

    private func openDictation(id: UUID, target: FocusTarget) {
        guard sessionGate.accepts(id) else { return }
        guard canDictate, active == nil, !finishing else {
            sessionGate.invalidate()
            state.session = .idle
            writeShowSettings()
            publishState()
            return
        }
        do {
            let bufferedWriter = try BufferedTextWriter(target: target)
            let stream = try engine.openStream()
            var writer: LiveTextWriter?
            do { writer = try LiveTextWriter(target: target, allowedModifiers: []) }
            catch InsertionError.liveUnsupported { writer = nil }
            catch {
                engine.cancel(stream: stream)
                throw error
            }
            let session = Dictation(id: id, stream: stream, target: target, bufferedWriter: bufferedWriter, liveWriter: writer)
            active = session
            state.audioLevel = 0
            try audio.start(moonshine: engine, stream: stream, onSpeech: {}, onLevel: { [weak self] level in
                guard let self, self.active?.id == id, case .listening = self.state.session else { return }
                self.state.audioLevel = level
                let now = ContinuousClock.now
                if now - self.lastLevelPublication >= .milliseconds(80) {
                    self.lastLevelPublication = now
                    self.publishState()
                }
            }, onFailure: { [weak self] message in
                guard let self else { return }
                self.failDictation(message, id: id)
            })
            state.session = .listening(buffered: session.buffered, text: session.fullText)
            session.pollTask = Task { [weak self] in await self?.poll(id: id) }
            publishState()
        } catch {
            if let session = active, session.id == id {
                audio.stop()
                engine.cancel(stream: session.stream)
                active = nil
            }
            sessionGate.invalidate()
            state.session = .recovery(message: error.localizedDescription, text: "")
            publishState()
        }
    }

    private func cancelTargetResolution() {
        targetResolutionTask?.cancel()
        targetResolutionTask = nil
        startingSessionID = nil
        if active == nil, case .starting = state.session {
            sessionGate.invalidate()
            state.session = .idle
        }
    }

    private func poll(id: UUID) async {
        while !Task.isCancelled, active?.id == id {
            do { try await Task.sleep(for: .milliseconds(240)) } catch { return }
            guard let session = active, session.id == id, !session.polling, !session.commitInFlight, !finishing else { continue }
            session.polling = true
            engine.transcribe(stream: session.stream) { [weak self] result in
                guard let self, self.sessionGate.accepts(id), let current = self.active, current.id == id else { return }
                self.receiveTranscript(result, session: current)
            }
        }
    }

    private func receiveTranscript(_ result: Result<[MoonshineLine], Error>, session: Dictation) {
        session.updateTask = Task { [weak self] in
            guard let self else { return }
            switch result {
            case let .success(lines): await self.didTranscribe(lines, session: session)
            case let .failure(error): self.failDictation(error.localizedDescription, id: session.id)
            }
            session.polling = false
            session.updateTask = nil
        }
    }

    private func didTranscribe(_ lines: [MoonshineLine], session: Dictation) async {
        guard sessionGate.accepts(session.id), active?.id == session.id, !finishing else { return }
        if !lines.isEmpty { session.ledger.update(lines) }
        let fullText = session.fullText
        if !state.preferences.keepLastTranscript { state.lastTranscript = "" }
        else if !fullText.isEmpty { state.lastTranscript = fullText }

        if let writer = session.liveWriter {
            do { try await writer.updateInEditor(session.ledger.livePendingText) }
            catch InsertionError.liveUnsupported { session.liveWriter = nil }
            catch { failDictation(error.localizedDescription, id: session.id); return }
        }

        guard sessionGate.accepts(session.id), active?.id == session.id, !finishing else { return }
        state.session = .listening(buffered: session.buffered, text: session.fullText)
        publishState()
    }

    private func commitBuffered(_ lines: [MoonshineLine], session: Dictation) {
        guard !session.commitInFlight else { return }
        session.commitInFlight = true
        let task = Task { [weak self] in
            guard let self else { return }
            do {
                try await self.commit(lines, session: session)
                guard self.active?.id == session.id else { return }
                session.commitInFlight = false
                session.commitTask = nil
                self.publishState()
            } catch { self.failDictation(error.localizedDescription, id: session.id) }
        }
        session.commitTask = task
    }

    private func commit(_ lines: [MoonshineLine], session: Dictation) async throws {
        guard sessionGate.accepts(session.id), active?.id == session.id else { return }
        let selected = lines.filter(\.complete)
        guard !selected.isEmpty else { return }
        if session.liveWriter != nil, !session.pendingLines.allSatisfy(\.complete) { return }
        let insertion = session.ledger.insertion(for: lines)
        guard !insertion.isEmpty else { return }
        if let writer = session.liveWriter {
            try await writer.updateInEditor(session.ledger.livePendingText)
            try writer.commit()
        } else {
            try await session.bufferedWriter.insert(insertion)
        }
        guard sessionGate.accepts(session.id), active?.id == session.id else { return }
        session.ledger.markCommitted(lines)
    }

    private func stopDictation() {
        holdTask?.cancel()
        holdTask = nil
        guard let session = active else {
            if startingSessionID != nil {
                cancelTargetResolution()
                state.session = .idle
                publishState()
            }
            return
        }
        guard !finishing else { return }
        finishing = true
        session.pollTask?.cancel()
        audio.stop()
        state.session = .finishing
        publishState()
        Task { [weak self] in
            await session.updateTask?.value
            await session.commitTask?.value
            guard let self, self.sessionGate.accepts(session.id), self.active?.id == session.id else { return }
            self.finishEngine(session)
        }
    }

    private func finishEngine(_ session: Dictation) {
        engine.finish(stream: session.stream) { [weak self] result in
            guard let self, self.sessionGate.accepts(session.id), self.active?.id == session.id else { return }
            switch result {
            case let .success(lines):
                session.updateTask = Task { await self.finishDictation(lines, session: session) }
            case let .failure(error): self.failDictation(error.localizedDescription, id: session.id)
            }
        }
    }

    private func finishDictation(_ lines: [MoonshineLine], session: Dictation) async {
        guard sessionGate.accepts(session.id), active?.id == session.id else { return }
        if !lines.isEmpty { session.ledger.update(lines) }
        if !state.preferences.keepLastTranscript { state.lastTranscript = "" }
        else if !session.fullText.isEmpty { state.lastTranscript = session.fullText }
        let pending = session.pendingLines
        if let writer = session.liveWriter {
            do {
                if !lines.isEmpty { try await writer.updateInEditor(session.ledger.livePendingText) }
                guard !pending.isEmpty, pending.allSatisfy(\.complete) else {
                    completeDictation(session)
                    return
                }
                try writer.commit()
                session.ledger.markCommitted(pending)
                completeDictation(session)
            } catch InsertionError.liveUnsupported {
                session.liveWriter = nil
                finishBuffered(session)
            } catch { failDictation(error.localizedDescription, id: session.id) }
        } else {
            finishBuffered(session)
        }
    }

    private func finishBuffered(_ session: Dictation) {
        let pending = session.ledger.committablePrefix
        guard !pending.isEmpty else {
            if session.pendingLines.isEmpty { completeDictation(session) }
            else { recoverUncommitted(session) }
            return
        }
        commitBuffered(pending, session: session)
        let task = session.commitTask
        guard let task else { return }
        Task { [weak self] in
            await task.value
            guard let self, self.sessionGate.accepts(session.id), self.active?.id == session.id else { return }
            if session.pendingLines.isEmpty { self.completeDictation(session) }
            else { self.recoverUncommitted(session) }
        }
    }

    private func recoverUncommitted(_ session: Dictation) {
        let text = session.pendingText
        guard !text.isEmpty else {
            completeDictation(session)
            return
        }
        active = nil
        sessionGate.invalidate()
        finishing = false
        state.session = .recovery(message: "Moonshine could not finish the last phrase. Copy it below to keep it.", text: text)
        publishState()
    }

    private func completeDictation(_ session: Dictation) {
        let text = session.fullText
        if !state.preferences.keepLastTranscript { state.lastTranscript = "" }
        else if !text.isEmpty { state.lastTranscript = text }
        active = nil
        sessionGate.invalidate()
        finishing = false
        state.session = .idle
        publishState()
    }

    private func cancelDictation(message: String, clearRecovery: Bool = false) {
        holdTask?.cancel()
        holdTask = nil
        cancelTargetResolution()
        guard let session = active else {
            finishing = false
            if case .recovery = state.session, !clearRecovery { return }
            state.session = .idle
            publishState()
            return
        }
        session.updateTask?.cancel()
        session.commitTask?.cancel()
        session.pollTask?.cancel()
        audio.stop()
        engine.cancel(stream: session.stream)
        let text = session.fullText
        if !state.preferences.keepLastTranscript { state.lastTranscript = "" }
        else if !text.isEmpty { state.lastTranscript = text }
        active = nil
        sessionGate.invalidate()
        finishing = false
        state.session = .recovery(message: message, text: text)
        publishState()
    }

    private func failDictation(_ message: String, id: UUID) {
        guard let session = active, session.id == id else { return }
        session.updateTask?.cancel()
        session.commitTask?.cancel()
        session.pollTask?.cancel()
        audio.stop()
        engine.cancel(stream: session.stream)
        let text = session.fullText
        if !state.preferences.keepLastTranscript { state.lastTranscript = "" }
        else if !text.isEmpty { state.lastTranscript = text }
        active = nil
        sessionGate.invalidate()
        finishing = false
        state.session = .recovery(message: message, text: text)
        publishState()
    }

    private func copyRecovery() {
        guard case let .recovery(_, text) = state.session, !text.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        state.session = .idle
    }

    private func copyLastTranscript() {
        guard !state.lastTranscript.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(state.lastTranscript, forType: .string)
    }

    private func shutdown() {
        permissionTimer?.invalidate()
        permissionTimer = nil
        downloadTask?.cancel()
        downloadTask = nil
        cancelDictation(message: "Voco closed during dictation. Your words are saved here.")
        shortcutMonitor.stop()
        NSApp.terminate(nil)
    }

    private func publishState() { writeMessage(["type": "state", "state": state.snapshot()]) }
    private func writeShowSettings() { writeMessage(["type": "showSettings"]) }

    private func writeError(_ message: String) {
        FileHandle.standardError.write(Data("Voco native: \(message)\n".utf8))
    }

    private func writeMessage(_ message: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: message, options: [.sortedKeys]) else {
            writeError("Could not encode a native protocol message.")
            return
        }
        outputLock.lock()
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data([0x0a]))
        outputLock.unlock()
    }

    private func readInput(
        onLine: @escaping @MainActor @Sendable (String) -> Void,
        onEnd: @escaping @MainActor @Sendable () -> Void
    ) {
        DispatchQueue.global(qos: .userInitiated).async {
            while let line = readLine() {
                DispatchQueue.main.sync { MainActor.assumeIsolated { onLine(line) } }
            }
            DispatchQueue.main.async { MainActor.assumeIsolated { onEnd() } }
        }
    }
}
