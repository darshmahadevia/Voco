import AppKit
@preconcurrency import ApplicationServices
import AVFoundation
import Darwin
import Foundation

@MainActor
final class NativeCoordinator {
    private final class Dictation {
        let id: UUID
        let engine: any SpeechEngine
        let stream: SpeechStreamID
        let target: FocusTarget
        let startedAt = ContinuousClock.now
        var fullText = ""
        var insertionTask: Task<Void, Never>?

        init(id: UUID, engine: any SpeechEngine, stream: SpeechStreamID, target: FocusTarget) {
            self.id = id
            self.engine = engine
            self.stream = stream
            self.target = target
        }

    }

    private let state = NativeStateStore()
    private var engine: any SpeechEngine
    private let audio = NativeAudioInput()
    private var lastLevelPublication = ContinuousClock.now
    private let moonshineModelDirectory: URL
    private let modelsRoot: URL
    private let hadSavedModelSelection: Bool
    private let shortcutMonitor = ShortcutMonitor()
    private var downloadTask: Task<Void, Never>?
    private var downloadGeneration: UUID?
    private var downloadModelID: SpeechModelID?
    private var activationGeneration: UUID?
    private var hasInspectedModels = false
    private enum CaptureMode { case hold, continuous }
    private struct PendingCapture {
        let id: UUID
        let target: FocusTarget
    }
    private var captureMode: CaptureMode?
    private var pendingCapture: PendingCapture?
    private var holdTask: Task<Void, Never>?
    private var targetResolutionTask: Task<Void, Never>?
    private var startingSessionID: UUID?
    private var permissionTimer: Timer?
    private var active: Dictation?
    private var sessionGate = SessionIDGate()
    private var finishing = false

    init(modelDirectory: URL) {
        let legacyDirectory = modelDirectory.standardizedFileURL
        moonshineModelDirectory = legacyDirectory
        modelsRoot = SpeechModelCatalog.modelsRoot(from: legacyDirectory)
        let defaults = NativePreferences.defaults
        hadSavedModelSelection = defaults.object(forKey: "selectedSpeechModel") != nil
        let storedModel = defaults.string(forKey: "selectedSpeechModel").flatMap(SpeechModelID.init(rawValue:)) ?? .moonshine
        state.selectedModel = storedModel
        state.recommendedModel = SpeechModelCatalog.recommendedModel
        engine = SpeechModelCatalog.makeEngine(for: storedModel)
        shortcutMonitor.onAction = { [weak self] action in
            switch action {
            case .pressed: self?.armHold()
            case .released: self?.releaseHold()
            case .cancelled:
                if self?.captureMode == .hold {
                    self?.cancelDictation(message: "Dictation canceled.", clearRecovery: true)
                }
            case .toggleContinuous: self?.toggleContinuous()
            }
        }
        shortcutMonitor.onEscape = { [weak self] in
            self?.cancelDictation(message: "Dictation canceled.", clearRecovery: true)
        }
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshPermissions(publish: true) }
        }
    }

    func start() {
        refreshPermissions(publish: false)
        Task { await loadInitialModels() }
        readInput(onLine: { [weak self] line in self?.receive(line) }, onEnd: { [weak self] in
            self?.shutdown()
        })
    }

    private func loadInitialModels() async {
        for modelID in SpeechModelID.allCases {
            let installer = ModelInstaller(modelDirectory: modelDirectory(for: modelID), modelID: modelID)
            let result = await Task.detached {
                Result { try installer.verifyCachedModel(verifyChecksums: false) }
            }.value
            guard case .missing = state.models[modelID] ?? .missing else { continue }
            switch result {
            case .success(true): state.models[modelID] = .installed
            case .success(false): state.models[modelID] = .missing
            case let .failure(error): state.models[modelID] = .error(error.localizedDescription)
            }
        }
        if !hadSavedModelSelection,
           case .missing = state.models[state.selectedModel] ?? .missing,
           let firstInstalled = SpeechModelCatalog.recommendedModel.flatMap({ candidate in
               if case .installed = state.models[candidate] { return candidate }
               return nil
           }) ?? SpeechModelID.allCases.first(where: { candidate in
               if case .installed = state.models[candidate] { return true }
               return false
           }) {
            state.selectedModel = firstInstalled
            engine = SpeechModelCatalog.makeEngine(for: firstInstalled)
        }
        hasInspectedModels = true
        syncSelectedModelState()
        if case .installed = state.models[state.selectedModel] {
            activateModel(state.selectedModel)
        } else {
            publishState()
        }
    }

    private func selectModel(_ modelID: SpeechModelID) throws {
        guard active == nil, startingSessionID == nil, !finishing, activationGeneration == nil else {
            throw NativeError.unavailable("Finish dictation before changing the speech model.")
        }
        switch state.models[modelID] ?? .missing {
        case .ready where modelID == state.selectedModel: return
        case .installed, .ready: activateModel(modelID)
        case .missing, .downloading, .loading:
            throw NativeError.unavailable("Install this speech model before selecting it.")
        case let .error(message):
            throw NativeError.unavailable("This speech model is unavailable. Download it again to repair it. \(message)")
        }
    }

    private func activateModel(_ modelID: SpeechModelID) {
        guard activationGeneration == nil, active == nil, startingSessionID == nil, !finishing else { return }
        if modelID == state.selectedModel, case .ready = state.models[modelID] { return }
        let generation = UUID()
        activationGeneration = generation
        let previousID = state.selectedModel
        let previousEngine = engine
        let candidate = SpeechModelCatalog.makeEngine(for: modelID)
        let targetDirectory = modelDirectory(for: modelID)
        state.selectedModel = modelID
        state.models[modelID] = .loading
        if previousID != modelID { state.models[previousID] = .installed }
        syncSelectedModelState()
        publishState()

        Task { [weak self] in
            await Task.detached(priority: .userInitiated) { previousEngine.unload() }.value
            guard let self, self.activationGeneration == generation else { return }
            candidate.warm(modelDirectory: targetDirectory) { [weak self] result in
                guard let self, self.activationGeneration == generation else {
                    candidate.unload()
                    return
                }
                switch result {
                case .success:
                    self.engine = candidate
                    self.state.selectedModel = modelID
                    self.state.models[modelID] = .ready
                    if previousID != modelID { self.state.models[previousID] = .installed }
                    NativePreferences.defaults.set(modelID.rawValue, forKey: "selectedSpeechModel")
                    self.activationGeneration = nil
                    self.syncSelectedModelState()
                    self.publishState()
                case let .failure(error):
                    candidate.unload()
                    self.state.models[modelID] = .error(error.localizedDescription)
                    guard previousID != modelID else {
                        self.activationGeneration = nil
                        self.syncSelectedModelState()
                        self.publishState()
                        return
                    }
                    self.state.models[previousID] = .loading
                    self.state.selectedModel = previousID
                    self.syncSelectedModelState()
                    self.publishState()
                    previousEngine.warm(modelDirectory: self.modelDirectory(for: previousID)) { [weak self] restoreResult in
                        guard let self, self.activationGeneration == generation else { return }
                        switch restoreResult {
                        case .success:
                            self.engine = previousEngine
                            self.state.models[previousID] = .ready
                        case let .failure(restoreError):
                            self.state.models[previousID] = .error(restoreError.localizedDescription)
                        }
                        self.activationGeneration = nil
                        self.syncSelectedModelState()
                        self.publishState()
                    }
                }
            }
        }
    }

    private func modelDirectory(for modelID: SpeechModelID) -> URL {
        if modelID == .moonshine { return moonshineModelDirectory }
        return SpeechModelCatalog.directory(for: modelID, in: modelsRoot)
    }

    private var hasReadyModel: Bool {
        state.models.values.contains { if case .ready = $0 { return true }; return false }
    }

    private func syncSelectedModelState() {
        state.model = state.models[state.selectedModel] ?? .missing
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
        case "downloadModel":
            guard let raw = command["modelId"] as? String, let modelID = SpeechModelID(rawValue: raw) else {
                throw NativeError.invalidCommand("Choose a supported speech model to download.")
            }
            try beginDownload(modelID)
        case "selectModel":
            guard let raw = command["modelId"] as? String, let modelID = SpeechModelID(rawValue: raw) else {
                throw NativeError.invalidCommand("Choose a supported speech model.")
            }
            try selectModel(modelID)
        case "cancelDownload": cancelDownload()
        case "requestMicrophone": requestMicrophone()
        case "requestAccessibility": requestAccessibility()
        case "openPrivacy":
            guard let pane = command["pane"] as? String, ["microphone", "accessibility"].contains(pane) else {
                throw NativeError.invalidCommand("Choose the microphone or accessibility privacy setting.")
            }
            openPrivacy(pane)
        case "setPreferences": try setPreferences(command["preferences"])
        case "setUsagePreferences":
            guard let goal = command["dailyGoal"] as? Int, (100...10000).contains(goal),
                  let wpm = command["typingWpm"] as? Int, (10...200).contains(wpm) else {
                throw NativeError.invalidCommand("Choose a valid word goal and typing speed.")
            }
            state.usage.dailyGoal = goal
            state.usage.typingWpm = wpm
        case "stop": stopDictation()
        case "cancel": cancelDictation(message: "Dictation canceled.", clearRecovery: true)
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

    private func beginDownload(_ modelID: SpeechModelID) throws {
        guard downloadTask == nil else {
            throw NativeError.unavailable("Another speech model is already downloading.")
        }
        switch state.models[modelID] ?? .missing {
        case .ready, .installed:
            return
        case .loading:
            throw NativeError.unavailable("This speech model is already loading.")
        case .downloading:
            throw NativeError.unavailable("This speech model is already downloading.")
        case .missing, .error:
            break
        }
        let installer = ModelInstaller(modelDirectory: modelDirectory(for: modelID), modelID: modelID)
        let generation = UUID()
        downloadGeneration = generation
        downloadModelID = modelID
        state.models[modelID] = .downloading(progress: 0, file: "Starting download…")
        syncSelectedModelState()
        publishState()
        downloadTask = Task { [weak self] in
            do {
                try await installer.download { [weak self] file, progress in
                    Task { @MainActor in
                        guard let self, self.downloadGeneration == generation else { return }
                        guard case .downloading = self.state.models[modelID] else { return }
                        self.state.models[modelID] = .downloading(progress: progress, file: file)
                        self.syncSelectedModelState()
                        self.publishState()
                    }
                }
                guard let self, self.downloadGeneration == generation, !Task.isCancelled else { return }
                self.downloadTask = nil
                self.downloadGeneration = nil
                self.downloadModelID = nil
                self.state.models[modelID] = .installed
                self.syncSelectedModelState()
                self.publishState()
                if self.active == nil, self.startingSessionID == nil, !self.finishing,
                   self.state.selectedModel == modelID || !self.hasReadyModel {
                    self.activateModel(modelID)
                }
            } catch is CancellationError {
                guard let self, self.downloadGeneration == generation else { return }
                self.downloadTask = nil
                self.downloadGeneration = nil
                self.downloadModelID = nil
                self.state.models[modelID] = .missing
                self.syncSelectedModelState()
                self.publishState()
            } catch {
                guard let self, self.downloadGeneration == generation else { return }
                self.downloadTask = nil
                self.downloadGeneration = nil
                self.downloadModelID = nil
                self.state.models[modelID] = .error(error.localizedDescription)
                self.syncSelectedModelState()
                self.publishState()
            }
        }
    }

    private func cancelDownload() {
        guard let downloadTask else { return }
        let modelID = downloadModelID
        downloadGeneration = nil
        self.downloadTask = nil
        downloadModelID = nil
        downloadTask.cancel()
        if let modelID { state.models[modelID] = .missing }
        syncSelectedModelState()
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
        } else if state.microphone != "granted", captureMode != nil || active != nil || startingSessionID != nil {
            cancelDictation(message: "Microphone access was turned off. Your words are saved here.")
        }
        if publish { publishState() }
    }

    private func armHold() {
        guard captureMode == nil, active == nil, startingSessionID == nil, !finishing else { return }
        guard let request = captureRequest() else { return }
        captureMode = .hold
        pendingCapture = request
        holdTask = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(140)) } catch { return }
            guard let self, self.pendingCapture?.id == request.id else { return }
            self.holdTask = nil
            self.pendingCapture = nil
            self.startDictation(id: request.id, target: request.target)
        }
    }

    private func captureRequest() -> PendingCapture? {
        guard canDictate, let target = FocusTarget.capture() else { writeShowSettings(); return nil }
        return PendingCapture(id: UUID(), target: target)
    }

    private func toggleContinuous() {
        guard !finishing else { return }
        if captureMode == .continuous {
            stopDictation()
            return
        }
        if captureMode == .hold {
            captureMode = .continuous
            if let request = pendingCapture {
                holdTask?.cancel()
                holdTask = nil
                pendingCapture = nil
                startDictation(id: request.id, target: request.target)
            }
            return
        }
        guard active == nil, startingSessionID == nil, let request = captureRequest() else { return }
        captureMode = .continuous
        startDictation(id: request.id, target: request.target)
    }

    private func releaseHold() {
        guard captureMode == .hold else { return }
        stopDictation()
    }

    private func clearCaptureIntent() {
        holdTask?.cancel()
        holdTask = nil
        pendingCapture = nil
        captureMode = nil
    }

    private var canDictate: Bool {
        if case .ready = state.model {
            return state.microphone == "granted" && state.accessibility && state.shortcut
        }
        return false
    }

    private func startDictation(id: UUID, target: FocusTarget) {
        guard canDictate, active == nil, !finishing else { clearCaptureIntent(); writeShowSettings(); return }
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
                self.clearCaptureIntent()
                self.state.session = .recovery(message: error.localizedDescription, text: "")
                self.publishState()
            }
        }
    }

    private func openDictation(id: UUID, target: FocusTarget) {
        guard sessionGate.accepts(id) else { return }
        guard canDictate, active == nil, !finishing else {
            sessionGate.invalidate()
            clearCaptureIntent()
            state.session = .idle
            writeShowSettings()
            publishState()
            return
        }
        do {
            _ = try target.validate()
            let sessionEngine = engine
            let stream = try sessionEngine.openStream()
            let session = Dictation(id: id, engine: sessionEngine, stream: stream, target: target)
            active = session
            state.audioLevel = 0
            state.audioWaveform = Array(repeating: 0, count: AudioMeter.barCount)
            try audio.start(engine: sessionEngine, stream: stream, onSpeech: {}, onLevel: { [weak self] level, waveform in
                guard let self, self.active?.id == id, case .listening = self.state.session else { return }
                self.state.audioLevel = level
                self.state.audioWaveform = waveform
                let now = ContinuousClock.now
                if now - self.lastLevelPublication >= .milliseconds(40) {
                    self.lastLevelPublication = now
                    self.publishState()
                }
            }, onFailure: { [weak self] message in
                guard let self else { return }
                self.failDictation(message, id: id)
            })
            state.session = .listening
            publishState()
        } catch {
            if let session = active, session.id == id {
                audio.stop()
                session.engine.cancel(stream: session.stream)
                active = nil
            }
            sessionGate.invalidate()
            clearCaptureIntent()
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
            clearCaptureIntent()
            state.session = .idle
        }
    }

    private func stopDictation() {
        clearCaptureIntent()
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
        audio.stop()
        state.session = .finishing
        publishState()
        session.engine.finish(stream: session.stream) { [weak self] result in
            guard let self, self.sessionGate.accepts(session.id), self.active?.id == session.id else { return }
            switch result {
            case let .success(lines):
                session.insertionTask = Task { await self.finishDictation(lines, session: session) }
            case let .failure(error): self.failDictation(error.localizedDescription, id: session.id)
            }
        }
    }

    private func finishDictation(_ lines: [SpeechLine], session: Dictation) async {
        guard sessionGate.accepts(session.id), active?.id == session.id else { return }
        session.fullText = TranscriptLedger.join(lines.map(\.text))
        guard !session.fullText.isEmpty else { completeDictation(session); return }
        guard lines.allSatisfy(\.complete) else { recoverUncommitted(session); return }
        do {
            try await session.target.insert(session.fullText)
            guard sessionGate.accepts(session.id), active?.id == session.id else { return }
            completeDictation(session)
        } catch is CancellationError {
            return
        } catch {
            failDictation(error.localizedDescription, id: session.id)
        }
    }

    private func recoverUncommitted(_ session: Dictation) {
        let text = session.fullText
        guard !text.isEmpty else {
            completeDictation(session)
            return
        }
        active = nil
        sessionGate.invalidate()
        finishing = false
        clearCaptureIntent()
        state.lastTranscript = state.preferences.keepLastTranscript ? text : ""
        state.session = .recovery(message: "Voco could not finish the last phrase. Copy it below to keep it.", text: text)
        publishState()
    }

    private func completeDictation(_ session: Dictation) {
        let text = session.fullText
        let elapsed = (ContinuousClock.now - session.startedAt).components
        state.usage.record(text: text, seconds: Double(elapsed.seconds) + Double(elapsed.attoseconds) / 1e18)
        if !state.preferences.keepLastTranscript { state.lastTranscript = "" }
        else if !text.isEmpty { state.lastTranscript = text }
        active = nil
        sessionGate.invalidate()
        finishing = false
        clearCaptureIntent()
        state.session = .idle
        publishState()
    }

    private func cancelDictation(message: String, clearRecovery: Bool = false) {
        clearCaptureIntent()
        cancelTargetResolution()
        guard let session = active else {
            finishing = false
            if case .recovery = state.session, !clearRecovery { return }
            state.session = .idle
            publishState()
            return
        }
        session.insertionTask?.cancel()
        audio.stop()
        session.engine.cancel(stream: session.stream)
        let text = session.fullText
        if !state.preferences.keepLastTranscript { state.lastTranscript = "" }
        else if !text.isEmpty { state.lastTranscript = text }
        active = nil
        sessionGate.invalidate()
        finishing = false
        clearCaptureIntent()
        state.session = text.isEmpty ? .idle : .recovery(message: message, text: text)
        publishState()
    }

    private func failDictation(_ message: String, id: UUID) {
        guard let session = active, session.id == id else { return }
        session.insertionTask?.cancel()
        audio.stop()
        session.engine.cancel(stream: session.stream)
        let text = session.fullText
        if !state.preferences.keepLastTranscript { state.lastTranscript = "" }
        else if !text.isEmpty { state.lastTranscript = text }
        active = nil
        sessionGate.invalidate()
        finishing = false
        clearCaptureIntent()
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
        engine.unload()
        shortcutMonitor.stop()
        NSApp.terminate(nil)
    }

    private func publishState() {
        guard hasInspectedModels else { return }
        writeMessage(["type": "state", "state": state.snapshot()])
    }
    private func writeShowSettings() { writeMessage(["type": "showSettings"]) }

    private func writeError(_ message: String) {
        FileHandle.standardError.write(Data("Voco native: \(message)\n".utf8))
    }

    private func writeMessage(_ message: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: message, options: [.sortedKeys]) else {
            writeError("Could not encode a native protocol message.")
            return
        }
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data([0x0a]))
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
