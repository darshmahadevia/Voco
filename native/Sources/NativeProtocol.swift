import AppKit
import ApplicationServices
import AVFoundation
import Foundation

struct NativePreferences: Codable, Equatable {
    var keepLastTranscript = true
    var outputMode: OutputMode = .fast

    static var defaults: UserDefaults {
        if let suite = ProcessInfo.processInfo.environment["VOCO_PREFERENCE_SUITE"],
           let defaults = UserDefaults(suiteName: suite) {
            return defaults
        }
        return .standard
    }

    static func load() -> NativePreferences {
        let defaults = Self.defaults
        let legacy = UserDefaults(suiteName: "org.vocoapp.Voco")
        if ProcessInfo.processInfo.environment["VOCO_SKIP_PREFERENCE_MIGRATION"] != "1" {
            for key in ["keepLastTranscript"] {
                if defaults.object(forKey: key) == nil, let value = legacy?.object(forKey: key) {
                    defaults.set(value, forKey: key)
                }
            }
        }
        let keep = defaults.object(forKey: "keepLastTranscript") as? Bool ?? true
        return NativePreferences(
            keepLastTranscript: keep,
            outputMode: defaults.string(forKey: "outputMode").flatMap(OutputMode.init(rawValue:)) ?? .fast
        )
    }

    func save() {
        let defaults = Self.defaults
        defaults.set(keepLastTranscript, forKey: "keepLastTranscript")
        defaults.set(outputMode.rawValue, forKey: "outputMode")
    }
}

enum NativeModelState {
    case missing
    case installed
    case downloading(progress: Double, file: String)
    case loading
    case ready
    case error(String)

    var json: [String: Any] {
        switch self {
        case .missing: ["kind": "missing"]
        case .installed: ["kind": "installed"]
        case let .downloading(progress, file): ["kind": "downloading", "progress": progress, "file": file]
        case .loading: ["kind": "loading"]
        case .ready: ["kind": "ready"]
        case let .error(message): ["kind": "error", "message": message]
        }
    }
}

enum NativeSessionState {
    case idle
    case starting
    case listening
    case finishing
    case polishing
    case recovery(message: String, text: String)

    var json: [String: Any] {
        switch self {
        case .idle: ["kind": "idle"]
        case .starting: ["kind": "starting"]
        case .listening: ["kind": "listening"]
        case .finishing: ["kind": "finishing"]
        case .polishing: ["kind": "polishing"]
        case let .recovery(message, text): ["kind": "recovery", "message": message, "text": text]
        }
    }
}

@MainActor
final class NativeStateStore {
    var model: NativeModelState { models[selectedModel] ?? .missing }
    var selectedModel: SpeechModelID = .moonshine
    var recommendedModel: SpeechModelID? = nil
    var models: [SpeechModelID: NativeModelState] = Dictionary(
        uniqueKeysWithValues: SpeechModelID.allCases.map { ($0, NativeModelState.missing) }
    )
    var session: NativeSessionState = .idle
    var preferences = NativePreferences.load() {
        didSet { preferences.save() }
    }
    var audioLevel: Double = 0
    var audioWaveform = Array(repeating: 0.0, count: 11)
    var usage = UsageStats.load(defaults: NativePreferences.defaults) {
        didSet { usage.save(defaults: NativePreferences.defaults) }
    }
    var lastTranscript = ""
    var lastRawTranscript = ""
    var polishNotice = ""
    var microphone: String = "required"
    var accessibility = false
    var shortcut = false

    func snapshot() -> [String: Any] {
        [
            "audioLevel": { if case .listening = session { return audioLevel }; return 0.0 }(),
            "audioWaveform": { if case .listening = session { return audioWaveform }; return Array(repeating: 0.0, count: 11) }(),
            "model": model.json,
            "selectedModel": selectedModel.rawValue,
            "recommendedModel": recommendedModel?.rawValue as Any? ?? NSNull(),
            "models": SpeechModelID.allCases.map { id in
                ["id": id.rawValue, "state": (models[id] ?? .missing).json]
            },
            "permissions": [
                "microphone": microphone,
                "accessibility": accessibility,
                "shortcut": shortcut,
            ],
            "session": session.json,
            "preferences": [
                "keepLastTranscript": preferences.keepLastTranscript,
                "outputMode": preferences.outputMode.rawValue,
            ],
            "lastTranscript": lastTranscript,
            "lastRawTranscript": lastRawTranscript,
            "polishNotice": polishNotice,
            "polishing": TranscriptPolisher.system.availability.json,
            "userName": NSFullUserName(),
            "usage": usage.json,
        ]
    }
}

enum NativeError: LocalizedError {
    case unavailable(String)
    case invalidCommand(String)
    case microphone
    case focus
    case noTranscript

    var errorDescription: String? {
        switch self {
        case let .unavailable(message): message
        case let .invalidCommand(message): message
        case .microphone: "Allow microphone access in System Settings, then try again."
        case .focus: "Voco could not safely reach the text field. Copy your words below and paste them where you want."
        case .noTranscript: "No speech was recognized. Try speaking a little closer to the microphone."
        }
    }
}

enum PermissionSnapshot {
    static func microphoneStatus() -> String {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: "granted"
        case .denied, .restricted: "denied"
        case .notDetermined: "required"
        @unknown default: "required"
        }
    }

    static var accessibilityAllowed: Bool { AXIsProcessTrusted() }
}
