import SwiftUI
import AVFoundation

struct PillView: View {
    @Bindable var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isRecovery: Bool {
        if case .recovery = model.phase { return true }
        return false
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                if model.phase == .starting || model.phase == .finishing {
                    ProgressView().controlSize(.mini)
                } else {
                    Image(systemName: isRecovery ? "text.bubble" : "mic.fill")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(isRecovery ? Color.orange : Color.primary)
                        .accessibilityLabel(model.continuousListening ? "Continuous listening" : model.phase.title)
                }
                if isRecovery {
                    Text(model.transcript)
                        .font(.system(size: 14))
                        .lineLimit(3)
                        .truncationMode(.head)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else if !model.liveTypingAvailable {
                    Text("Buffered")
                        .font(.system(size: 11, weight: .medium))
                        .lineLimit(1)
                        .foregroundStyle(.secondary)
                }
                if model.continuousListening && model.phase == .listening {
                    Button { model.stopListening() } label: {
                        Image(systemName: "stop.fill").font(.system(size: 10))
                    }
                    .buttonStyle(.plain)
                    .help("Stop listening and insert remaining words")
                    .accessibilityLabel("Stop listening")
                }
            }
            if case .recovery(let message) = model.phase {
                Text(message).font(.system(size: 12)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Button("Copy text") { model.copyTranscript() }
                        .buttonStyle(.borderedProminent)
                        .disabled(model.transcript.isEmpty)
                    Button("Dismiss") { model.cancel() }.buttonStyle(.bordered)
                }.controlSize(.small)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, isRecovery ? 14 : 11)
        .frame(width: isRecovery ? 340 : !model.liveTypingAvailable ? (model.continuousListening ? 112 : 108) : model.continuousListening ? 80 : 50, alignment: .leading)
        .background {
            if isRecovery {
                RoundedRectangle(cornerRadius: 20).fill(.regularMaterial)
            } else {
                Capsule().fill(.regularMaterial)
            }
        }
        .shadow(color: .black.opacity(0.16), radius: 10, x: 0, y: 4)
        .padding(12)
        .fixedSize(horizontal: false, vertical: true)
        .onGeometryChange(for: CGSize.self) { $0.size } action: { model.pillSizeChanged?($0) }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: isRecovery)
        .help(!model.liveTypingAvailable ? "This field inserts text after release or a pause." : model.continuousListening ? "Press Fn + Space to stop. Esc stops without removing typed words." : "Release \(model.shortcut.label) to stop. Esc stops without removing typed words.")
    }

}

struct SetupView: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(alignment: .top, spacing: 16) {
                Image(systemName: "waveform")
                    .font(.system(size: 32, weight: .medium))
                    .frame(width: 52, height: 56)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Voco").font(.system(size: 28, weight: .semibold))
                    Text("Words appear where you type. Hold to talk or use Fn + Space.")
                        .font(.system(size: 14)).foregroundStyle(.secondary)
                }
            }
            VStack(spacing: 0) {
                setupRow(
                    symbol: "mic", title: "English speech", detail: model.setupMessage,
                    complete: model.speechReady, action: model.prepare,
                    button: model.isPreparing ? "Preparing…" : "Prepare"
                )
                if let progress = model.downloadProgress {
                    ProgressView(value: progress).padding(.leading, 36).padding(.bottom, 14)
                        .accessibilityLabel("English model download")
                }
                if !model.microphoneAllowed && AVCaptureDevice.authorizationStatus(for: .audio) == .denied {
                    Button("Open microphone settings") { model.openPrivacy("Microphone") }
                        .padding(.leading, 36).padding(.bottom, 14)
                }
                Divider()
                setupRow(
                    symbol: "keyboard", title: "Keyboard access", detail: "Use your talk key in other apps and insert your words.",
                    complete: model.keyboardAllowed, action: model.requestAccessibility, button: "Allow"
                )
                if !model.accessibilityAllowed {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("In \(model.keyboardPermissionName), enable Voco. If it is missing, click + and select the Voco app shown in Finder.")
                            .font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        Button("Show Voco in Finder") { model.revealApp() }.buttonStyle(.link).font(.system(size: 12))
                    }
                    .padding(.leading, 36).padding(.bottom, 14)
                }
            }
            HStack {
                Text("Talk key").font(.system(size: 13, weight: .medium))
                Spacer()
                Picker("Talk key", selection: $model.shortcut) {
                    ForEach(TalkKey.allCases) { key in Text(key.label).tag(key) }
                }
                .labelsHidden().frame(width: 170)
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("Hold to dictate; release to stop. Fn + Space toggles continuous listening.")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Text("Pause between phrases").font(.system(size: 13))
                    Spacer()
                    Picker("Pause between phrases", selection: $model.pauseSeconds) {
                        Text("1 second").tag(1.0)
                        Text("1.5 seconds").tag(1.5)
                        Text("2 seconds").tag(2.0)
                        Text("3 seconds").tag(3.0)
                    }.labelsHidden().frame(width: 170)
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                Toggle("Keep last transcript available to copy", isOn: $model.keepLastTranscript)
                    .font(.system(size: 13))
                Text("Enabled by default. Keeps one transcript in memory until you quit. Turn it off to clear it.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                HStack {
                    Button("Copy last transcript") { model.copyLastTranscript() }
                        .disabled(model.lastTranscript.isEmpty)
                    if !model.lastTranscript.isEmpty {
                        Text("\(model.lastTranscript.count) characters saved").foregroundStyle(.secondary)
                    }
                }.font(.system(size: 12))
            }
            if model.shortcut == .fn {
                VStack(alignment: .leading, spacing: 6) {
                    Text("In Keyboard settings, set “Press Globe key to” to “Do Nothing” to keep Apple's shortcut from opening.")
                        .font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    Button("Open Keyboard settings") {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension") {
                            NSWorkspace.shared.open(url)
                        }
                    }.buttonStyle(.link).font(.system(size: 12))
                }
            }
            HStack(spacing: 8) {
                Image(systemName: model.isReady ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(model.isReady ? Color.green : Color.secondary)
                Text(model.isReady ? "Ready. Click a text field, then hold \(model.shortcut.label)." : "Finish setup, then click a text field to try dictation.")
                    .font(.system(size: 12))
            }
            Text("Speech is processed on your Mac. No account, API key, or subscription.")
                .font(.system(size: 11)).foregroundStyle(.secondary)
        }
        .padding(30)
        .frame(width: 550)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func setupRow(
        symbol: String, title: String, detail: String, complete: Bool,
        action: @escaping () -> Void, button: String
    ) -> some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: symbol).font(.system(size: 17)).frame(width: 22).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 13, weight: .semibold))
                Text(detail).font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            if complete {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).accessibilityLabel("Allowed")
            } else {
                Button(button, action: action)
                    .disabled(title == "English speech" && model.isPreparing)
                    .controlSize(.small)
            }
        }
        .padding(.vertical, 16)
    }
}
