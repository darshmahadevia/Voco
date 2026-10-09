import AppKit
import ApplicationServices
import AVFoundation
import Foundation

struct NativePreferences: Codable, Equatable {
    var keepLastTranscript = true

    static func load() -> NativePreferences {
        let defaults = UserDefaults.standard
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
            keepLastTranscript: keep
        )
    }

    func save() {
        let defaults = UserDefaults.standard
        defaults.set(keepLastTranscript, forKey: "keepLastTranscript")
    }
}

enum NativeModelState {
    case missing
    case downloading(progress: Double, file: String)
    case loading
    case ready
    case error(String)

    var json: [String: Any] {
        switch self {
        case .missing: ["kind": "missing"]
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
    case listening(buffered: Bool, text: String)
    case finishing
    case recovery(message: String, text: String)

    var json: [String: Any] {
        switch self {
        case .idle: ["kind": "idle"]
        case .starting: ["kind": "starting"]
        case let .listening(buffered, text): ["kind": "listening", "mode": "hold", "buffered": buffered, "text": text]
        case .finishing: ["kind": "finishing"]
        case let .recovery(message, text): ["kind": "recovery", "message": message, "text": text]
        }
    }
}

@MainActor
final class NativeStateStore {
    var model: NativeModelState = .missing
    var session: NativeSessionState = .idle
    var preferences = NativePreferences.load() {
        didSet { preferences.save() }
    }
    var audioLevel: Double = 0
    var lastTranscript = ""
    var microphone: String = "required"
    var accessibility = false
    var shortcut = false

    func snapshot() -> [String: Any] {
        [
            "audioLevel": { if case .listening = session { return audioLevel }; return 0.0 }(),
            "model": model.json,
            "permissions": [
                "microphone": microphone,
                "accessibility": accessibility,
                "shortcut": shortcut,
            ],
            "session": session.json,
            "preferences": [
                "keepLastTranscript": preferences.keepLastTranscript,
            ],
            "lastTranscript": lastTranscript,
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
