final class FixtureSpeechEngine: SpeechEngine, @unchecked Sendable {
    let descriptor: SpeechModelDescriptor
    var audioSamples = 0
    var polls = 0
    var finishes = 0
    var cancellations = 0
    var failOpening = false
    var completion: (@MainActor @Sendable (Result<[SpeechLine], Error>) -> Void)?

    init(_ id: SpeechModelID) {
        descriptor = SpeechModelDescriptor(id: id, name: id.rawValue, modelVersion: "fixture", language: "English", license: "fixture")
    }

    func warm(modelDirectory: URL, completion: @escaping @MainActor @Sendable (Result<Void, Error>) -> Void) {}
    func loadIfNeeded(modelDirectory: URL) throws {}
    func unload() {}
    func openStream() throws -> SpeechStreamID {
        if failOpening { throw NativeError.unavailable("Opening failed.") }
        return SpeechStreamID()
    }
    func addAudio(_ samples: UnsafeBufferPointer<Float>, to stream: SpeechStreamID) throws { audioSamples += samples.count }
    func enqueueAudio(_ samples: UnsafeBufferPointer<Float>, to stream: SpeechStreamID, onFailure: @escaping @Sendable (String) -> Void) {
        audioSamples += samples.count
    }
    func transcribe(stream: SpeechStreamID, completion: @escaping @MainActor @Sendable (Result<[SpeechLine], Error>) -> Void) {
        polls += 1
    }
    func finish(stream: SpeechStreamID, completion: @escaping @MainActor @Sendable (Result<[SpeechLine], Error>) -> Void) {
        finishes += 1
        self.completion = completion
    }
    func finishSynchronously(stream: SpeechStreamID) throws -> [SpeechLine] { [] }
    func cancel(stream: SpeechStreamID) { cancellations += 1 }

    @MainActor func deliver(_ lines: [SpeechLine]) {
        let callback = completion
        completion = nil
        callback?(.success(lines))
    }
}

enum SpeechModelCatalog {
    static let recommendedModel: SpeechModelID? = nil
    static func modelsRoot(from directory: URL) -> URL { directory }
    static func directory(for id: SpeechModelID, in root: URL) -> URL { root.appendingPathComponent(id.rawValue) }
    static func makeEngine(for id: SpeechModelID) -> any SpeechEngine { FixtureSpeechEngine(id) }
}

final class ModelInstaller: Sendable {
    init(modelDirectory: URL, modelID: SpeechModelID) {}
    func verifyCachedModel(verifyChecksums: Bool) throws -> Bool { false }
    func download(onProgress: @escaping @Sendable (String, Double) -> Void) async throws {}
}

@MainActor final class NativeAudioInput {
    private(set) var recording = false
    func start(engine: any SpeechEngine, stream: SpeechStreamID, onSpeech: @escaping @MainActor () -> Void,
               onLevel: @escaping @MainActor @Sendable (Double, [Double]) -> Void, onFailure: @escaping @MainActor (String) -> Void) throws {
        recording = true
        Array(repeating: Float(0.25), count: 16_000).withUnsafeBufferPointer {
            engine.enqueueAudio($0, to: stream, onFailure: { _ in })
        }
    }
    func stop() { recording = false }
}

@MainActor final class ShortcutMonitor {
    enum Action { case pressed, released, cancelled, toggleContinuous }
    var onAction: ((Action) -> Void)?
    var onEscape: (() -> Void)?
    var isRunning = false
    func start() -> Bool { isRunning = true; return true }
    func stop() { isRunning = false }
}

actor SuspendedPolish {
    private var continuation: CheckedContinuation<String, Never>?
    func generate(_ raw: String) async -> String {
        await withCheckedContinuation { continuation = $0 }
    }
    func resume(_ text: String) { continuation?.resume(returning: text); continuation = nil }
}

extension NativeCoordinator {
    fileprivate func prepare(_ id: SpeechModelID) -> FixtureSpeechEngine {
        permissionTimer?.invalidate()
        permissionTimer = nil
        let fixture = FixtureSpeechEngine(id)
        engine = fixture
        state.selectedModel = id
        state.model = .ready
        state.models[id] = .ready
        state.microphone = "granted"
        state.accessibility = true
        state.shortcut = true
        return fixture
    }

    fileprivate func shortDeadlines() { recognitionTimeout = .milliseconds(100); cleanupTimeout = .milliseconds(100) }
    fileprivate func chooseOutput(_ mode: OutputMode) { state.preferences.outputMode = mode }
    fileprivate func usePolisher(_ value: TranscriptPolisher) { polisherOverride = value }
    fileprivate var rawText: String { state.lastRawTranscript }
    fileprivate var notice: String { state.polishNotice }
    fileprivate func press() { shortcutMonitor.onAction?(.pressed) }
    fileprivate func toggle() { shortcutMonitor.onAction?(.toggleContinuous) }
    fileprivate func combination() { shortcutMonitor.onAction?(.cancelled) }
    fileprivate func release() { shortcutMonitor.onAction?(.released) }
    fileprivate func escape() { shortcutMonitor.onEscape?() }
    fileprivate var snapshot: [String: Any] { state.session.json }
    fileprivate var recording: Bool { audio.recording }
    fileprivate var retainedText: String { state.lastTranscript }
    fileprivate var usageTotals: (words: Int, sessions: Int) {
        state.usage.days.values.reduce((words: 0, sessions: 0)) { ($0.words + $1.words, $0.sessions + $1.sessions) }
    }
    fileprivate func revokeMicrophone() {
        state.microphone = "denied"
        cancelDictation(message: "Microphone access was turned off.")
    }
    fileprivate func restoreMicrophone() { state.microphone = "granted" }
    fileprivate func enableRetention() { state.preferences.keepLastTranscript = true }
    fileprivate func disableRetention() { state.preferences.keepLastTranscript = false }
}

@main enum DeferredDictationCheck {
    @MainActor static func main() async throws {
        guard let suite = ProcessInfo.processInfo.environment["VOCO_PREFERENCE_SUITE"],
              suite.hasPrefix("Voco-deferred-check-") else {
            fatalError("Run scripts/check-deferred-dictation.sh to isolate preferences.")
        }
        defer {
            UserDefaults.standard.removePersistentDomain(forName: suite)
        }
        func final(_ text: String, complete: Bool = true) -> SpeechLine {
            SpeechLine(text: text, complete: complete)
        }
        func settle() async throws { try await Task.sleep(for: .milliseconds(220)) }

        NativePreferences.defaults.removeObject(forKey: "outputMode")
        precondition(NativePreferences.load().outputMode == .fast)
        NativePreferences(keepLastTranscript: true, outputMode: .balanced).save()
        precondition(NativePreferences.load().outputMode == .balanced)
        precondition(NativeSessionState.polishing.json["kind"] as? String == "polishing")
        NativePreferences.defaults.set("fast", forKey: "outputMode")
        let stateStore = NativeStateStore()
        stateStore.lastRawTranscript = "Memory only"
        stateStore.polishNotice = "Ephemeral"
        let stateSnapshot = stateStore.snapshot()
        precondition((stateSnapshot["preferences"] as? [String: Any])?["outputMode"] as? String == "fast")
        precondition(stateSnapshot["lastRawTranscript"] as? String == "Memory only")
        precondition(stateSnapshot["polishNotice"] as? String == "Ephemeral")
        precondition((stateSnapshot["polishing"] as? [String: Any])?["message"] is String)
        precondition(NativePreferences.defaults.object(forKey: "lastRawTranscript") == nil)
        precondition(NativePreferences.defaults.object(forKey: "polishNotice") == nil)

        for id in SpeechModelID.allCases {
            InsertionFixture.reset(web: true)
            NativePreferences.defaults.set(true, forKey: "keepLastTranscript")
            NativePreferences.defaults.removeObject(forKey: "usageStats.v1")
            let coordinator = NativeCoordinator(modelDirectory: URL(fileURLWithPath: "/tmp/voco-fixture-model"))
            let engine = coordinator.prepare(id)
            coordinator.press()
            try await settle()
            precondition(coordinator.snapshot["kind"] as? String == "listening" && coordinator.recording)
            precondition(engine.audioSamples == 16_000 && engine.polls == 0 && engine.finishes == 0)
            precondition(InsertionFixture.text == "Before. " && InsertionFixture.pastes == 0 && InsertionFixture.keyboardEvents == 0)
            coordinator.release()
            coordinator.release()
            precondition(coordinator.snapshot["kind"] as? String == "finishing" && !coordinator.recording)
            precondition(engine.finishes == 1 && InsertionFixture.pastes == 0)
            InsertionFixture.selection = CFRange(location: 0, length: 0)
            InsertionFixture.flags = .maskSecondaryFn
            engine.deliver([final("Final words."), final("Another phrase.")])
            try await Task.sleep(for: .milliseconds(35))
            precondition(coordinator.snapshot["kind"] as? String == "finishing")
            precondition(coordinator.retainedText.isEmpty, "A pending insertion must not publish a completed transcript")
            precondition(coordinator.usageTotals == (words: 0, sessions: 0))
            InsertionFixture.flags = []
            try await settle()
            precondition(InsertionFixture.text == "Final words. Another phrase.Before. " && InsertionFixture.pastes == 1)
            precondition(coordinator.snapshot["kind"] as? String == "idle")
            precondition(coordinator.retainedText == "Final words. Another phrase.")
            precondition(coordinator.usageTotals == (words: 4, sessions: 1))
            precondition(NSPasteboard.general.string(forType: .string) == "Original clipboard")

            InsertionFixture.reset(web: true)
            coordinator.press()
            try await settle()
            coordinator.release()
            let stale = engine.completion
            coordinator.escape()
            coordinator.press()
            try await settle()
            stale?(.success([final("Canceled words.")]))
            try await settle()
            precondition(coordinator.snapshot["kind"] as? String == "listening")
            precondition(InsertionFixture.pastes == 0 && InsertionFixture.text == "Before. ")
            coordinator.release()
            engine.deliver([final("New words.")])
            try await settle()
            precondition(InsertionFixture.text == "Before. New words." && InsertionFixture.pastes == 1)
            precondition(coordinator.usageTotals == (words: 6, sessions: 2))

            InsertionFixture.reset(web: true)
            coordinator.press()
            try await settle()
            coordinator.release()
            InsertionFixture.flags = .maskSecondaryFn
            engine.deliver([final("Do not paste.")])
            try await Task.sleep(for: .milliseconds(35))
            coordinator.escape()
            InsertionFixture.flags = []
            try await settle()
            precondition(InsertionFixture.pastes == 0 && InsertionFixture.text == "Before. ")
            precondition(coordinator.snapshot["text"] as? String == "Do not paste.")

            InsertionFixture.reset(web: true)
            coordinator.disableRetention()
            coordinator.press()
            try await settle()
            coordinator.release()
            InsertionFixture.changedFocus = true
            engine.deliver([final("Recover these words.")])
            try await settle()
            precondition(InsertionFixture.pastes == 0 && InsertionFixture.text == "Before. ")
            precondition(coordinator.snapshot["kind"] as? String == "recovery")
            precondition(coordinator.snapshot["text"] as? String == "Recover these words." && coordinator.retainedText.isEmpty)
            precondition(coordinator.usageTotals == (words: 6, sessions: 2))

            InsertionFixture.reset(web: true)
            coordinator.press()
            try await settle()
            coordinator.release()
            engine.deliver([final("Private progress.")])
            try await settle()
            precondition(coordinator.retainedText.isEmpty && coordinator.usageTotals == (words: 8, sessions: 3))
            let restored = UsageStats.load(defaults: NativePreferences.defaults)
            precondition(restored.days.values.reduce(0) { $0 + $1.words } == 8)


            InsertionFixture.reset(web: true)
            coordinator.press()
            try await settle()
            coordinator.release()
            coordinator.enableRetention()
            engine.deliver([final("Complete prefix."), final("Unfinished suffix", complete: false)])
            try await settle()
            precondition(InsertionFixture.pastes == 0 && InsertionFixture.text == "Before. ")
            precondition(coordinator.snapshot["text"] as? String == "Complete prefix. Unfinished suffix")
            precondition(coordinator.retainedText == "Complete prefix. Unfinished suffix")
            coordinator.disableRetention()

            InsertionFixture.reset(web: true)
            coordinator.press()
            try await settle()
            coordinator.release()
            engine.deliver([])
            try await settle()
            precondition(coordinator.snapshot["kind"] as? String == "idle" && InsertionFixture.pastes == 0)
            coordinator.press()
            try await settle()
            coordinator.release()
            engine.completion?(.failure(NativeError.unavailable("Recognition failed.")))
            engine.completion = nil
            precondition(coordinator.snapshot["kind"] as? String == "recovery" && InsertionFixture.pastes == 0)
            precondition(coordinator.snapshot["message"] as? String == "Recognition failed.")
            precondition(coordinator.usageTotals == (words: 8, sessions: 3))
            coordinator.escape()
            coordinator.press()
            coordinator.release()
            try await settle()
            precondition(coordinator.snapshot["kind"] as? String == "idle" && !coordinator.recording)
            coordinator.press()
            try await settle()
            coordinator.escape()
            precondition(coordinator.snapshot["kind"] as? String == "idle" && !coordinator.recording)
            precondition(engine.polls == 0 && InsertionFixture.pastes == 0)
            InsertionFixture.reset(web: true)
            coordinator.press()
            coordinator.toggle()
            coordinator.release()
            try await settle()
            precondition(coordinator.recording && coordinator.snapshot["kind"] as? String == "listening")
            precondition(InsertionFixture.pastes == 0)
            coordinator.combination()
            coordinator.press()
            coordinator.release()
            precondition(coordinator.recording)
            coordinator.toggle()
            precondition(coordinator.snapshot["kind"] as? String == "finishing")
            let samplesBeforeFinish = engine.audioSamples
            coordinator.toggle()
            coordinator.press()
            coordinator.release()
            precondition(engine.audioSamples == samplesBeforeFinish)
            engine.deliver([final("Continuous words.")])
            try await settle()
            precondition(InsertionFixture.text == "Before. Continuous words." && InsertionFixture.pastes == 1)

            InsertionFixture.reset(web: true)
            coordinator.press()
            try await settle()
            let samplesBeforePromotion = engine.audioSamples
            coordinator.toggle()
            coordinator.release()
            try await settle()
            precondition(coordinator.recording && engine.audioSamples == samplesBeforePromotion)
            coordinator.escape()
            precondition(!coordinator.recording && coordinator.snapshot["kind"] as? String == "idle")
            coordinator.toggle()
            try await settle()
            coordinator.toggle()
            engine.completion?(.failure(NativeError.unavailable("Continuous recognition failed.")))
            engine.completion = nil
            precondition(coordinator.snapshot["kind"] as? String == "recovery" && !coordinator.recording)
            coordinator.press()
            try await settle()
            coordinator.release()
            engine.deliver([final("Hold works again.")])
            try await settle()
            precondition(InsertionFixture.text == "Before. Hold works again." && InsertionFixture.pastes == 1)

            InsertionFixture.reset(web: true)
            coordinator.toggle()
            try await settle()
            coordinator.revokeMicrophone()
            precondition(!coordinator.recording)
            coordinator.toggle()
            try await settle()
            precondition(!coordinator.recording)
            coordinator.restoreMicrophone()
            engine.failOpening = true
            coordinator.toggle()
            try await settle()
            precondition(coordinator.snapshot["kind"] as? String == "recovery" && !coordinator.recording)
            engine.failOpening = false
            coordinator.press()
            try await settle()
            coordinator.release()
            engine.deliver([])
            try await settle()
            precondition(coordinator.snapshot["kind"] as? String == "idle")
            InsertionFixture.reset()
            InsertionFixture.partialWrite = true
            coordinator.press()
            try await settle()
            coordinator.release()
            engine.deliver([final("Keep the complete transcript.")])
            try await settle()
            precondition(InsertionFixture.text == "Before. Wrong" && InsertionFixture.axWrites == 1)
            precondition(InsertionFixture.pastes == 0)
            precondition(coordinator.snapshot["kind"] as? String == "recovery")
            precondition(coordinator.snapshot["text"] as? String == "Keep the complete transcript.")
            InsertionFixture.reset(web: true)
            coordinator.enableRetention()
            coordinator.chooseOutput(.balanced)
            coordinator.press()
            // A capture freezes output mode before the hold delay and target resolution.
            coordinator.chooseOutput(.fast)
            try await settle()
            coordinator.release()
            engine.deliver([final("um Alice has 12 tickets not 13")])
            try await settle()
            precondition(InsertionFixture.text == "Before. Alice has 12 tickets not 13")
            precondition(coordinator.rawText == "um Alice has 12 tickets not 13")

            InsertionFixture.reset(web: true)
            let suspended = SuspendedPolish()
            coordinator.usePolisher(TranscriptPolisher(availability: .init(available: true, message: "fixture")) {
                await suspended.generate($0)
            })
            coordinator.chooseOutput(.accurate)
            coordinator.press()
            try await settle()
            coordinator.release()
            engine.deliver([final("um Alice has 12 tickets")])
            try await settle()
            precondition(coordinator.snapshot["kind"] as? String == "polishing")
            precondition(coordinator.rawText == "um Alice has 12 tickets")
            precondition(InsertionFixture.pastes == 0)
            coordinator.escape()
            precondition(coordinator.snapshot["text"] as? String == "um Alice has 12 tickets")
            coordinator.chooseOutput(.fast)
            coordinator.press()
            try await settle()
            await suspended.resume("Alice has 12 tickets.")
            try await settle()
            precondition(coordinator.snapshot["kind"] as? String == "listening")
            precondition(InsertionFixture.pastes == 0 && InsertionFixture.text == "Before. ")
            coordinator.release()
            engine.deliver([final("New session words.")])
            try await settle()
            precondition(InsertionFixture.text == "Before. New session words.")

            InsertionFixture.reset(web: true)
            coordinator.chooseOutput(.accurate)
            coordinator.usePolisher(TranscriptPolisher(availability: .init(available: true, message: "fixture")) { _ in "" })
            coordinator.press()
            try await settle()
            coordinator.release()
            engine.deliver([final("um keep every original word")])
            try await settle()
            precondition(InsertionFixture.text == "Before. Keep every original word")
            precondition(!coordinator.notice.isEmpty)
            InsertionFixture.reset()
            coordinator.chooseOutput(.balanced)
            coordinator.press()
            try await settle()
            coordinator.release()
            engine.deliver([final("um")])
            try await settle()
            precondition(coordinator.retainedText.isEmpty && coordinator.rawText == "um")
            precondition(coordinator.notice.contains("Nothing was inserted"))
            precondition(InsertionFixture.text == "Before. ")
            coordinator.shortDeadlines()
            coordinator.chooseOutput(.fast)
            InsertionFixture.reset()
            coordinator.press()
            try await settle()
            coordinator.release()
            try await Task.sleep(for: .milliseconds(180))
            precondition(coordinator.snapshot["kind"] as? String == "recovery")
            precondition(InsertionFixture.text == "Before. ")
            engine.deliver([SpeechLine(text: "Late words.", complete: true)])
            try await Task.sleep(for: .milliseconds(50))
            precondition(InsertionFixture.text == "Before. ")

            let delayedPolish = SuspendedPolish()
            coordinator.usePolisher(TranscriptPolisher(availability: .init(available: true, message: "fixture")) {
                await delayedPolish.generate($0)
            })
            coordinator.chooseOutput(.accurate)
            coordinator.press()
            try await settle()
            coordinator.release()
            engine.deliver([SpeechLine(text: "um Keep 12 tickets.", complete: true)])
            try await Task.sleep(for: .milliseconds(200))
            precondition(coordinator.snapshot["kind"] as? String == "idle")
            precondition(InsertionFixture.text == "Before. Keep 12 tickets.")
            precondition(coordinator.notice.contains("too long") && coordinator.notice.contains("Kept basic cleanup"))
            precondition(coordinator.rawText == "um Keep 12 tickets.")
            await delayedPolish.resume("Keep 12 tickets.")
            try await Task.sleep(for: .milliseconds(50))
            precondition(InsertionFixture.text == "Before. Keep 12 tickets.")
            print("PASS \(id.rawValue): recognition deadline, basic cleanup fallback on cleanup deadline, late results ignored")
            coordinator.chooseOutput(.fast)
            print("PASS \(id.rawValue): output mode persistence/freeze, raw before cleanup, suspended cleanup cancellation/stale result, unsafe output fallback")
            print("PASS \(id.rawValue): capture, release, one paste, current cursor, cancellation, stale result, recovery, silence, tap, continuous promotion/stop/cancel/failure/permissions")
        }
    }
}
