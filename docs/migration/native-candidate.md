# Candidate A: Swift native runtime, Electron UI

Historical document for an earlier Voco implementation. Commands and design details below may refer to removed code. See the [current README](../../README.md), [architecture](../architecture.md), and [development guide](../development.md).

## Recommendation

Keep one signed Swift helper process as Voco's macOS system-integration and dictation runtime. Electron's main process owns the app lifecycle and windows. React owns the minimal setup/settings and microphone-pill views. The helper owns global shortcuts, microphone capture, Moonshine, focus tracking, live typing, and safe insertion. This keeps the existing trusted insertion boundary intact while replacing the Apple Speech framework with Moonshine.

The current seams map cleanly: `ShortcutMonitor`, `TextInsertion`/`FocusTarget`, and `LiveTextWriter` remain Swift. `AppModel` becomes a UI-free `DictationCoordinator` that publishes a snapshot and accepts typed commands. `SpeechSession` becomes `MoonshineEngine`; remove its Speech/SpeechAnalyzer implementation rather than retaining a compatibility path. `VocoCore` can continue to provide portable gesture/text helpers where their semantics still apply.

## Module map

```text
apps/desktop/src/main/
  main.ts                 Electron lifecycle, tray, windows, helper supervision
  nativeBridge.ts         JSONL request/response client and typed event fanout
apps/desktop/src/preload/
  index.ts                contextBridge exposing the narrow VocoApi only
apps/desktop/src/renderer/
  App.tsx                 setup, permissions, shortcut/pause settings
  Pill.tsx                ready/listening/finishing/recovery states
  styles.css              minimal token set; Motion only for small state transitions
native/VocoNative/
  Package.swift           macOS helper executable plus MoonshineVoice dependency
  Sources/VocoNative/
    main.swift            JSONL stdio host; logs go to stderr
    DictationCoordinator.swift  session state, shortcuts, insertion orchestration
    MoonshineEngine.swift       C API handles, model download, PCM and transcript conversion
    ShortcutMonitor.swift       existing global hold and Fn+Space monitor
    FocusTarget.swift           existing focused-app capture and validation
    TextInsertion.swift         existing guarded AX/pasteboard insertion
    LiveTextWriter.swift        existing live replacement path
```

The helper must be resolved relative to `process.resourcesPath` in packaged builds, never by a shell command or a PATH lookup. Electron should start it with an explicit executable URL, keep stdin/stdout pipes, restart it only after an unexpected exit, and show an unavailable state until it sends a fresh snapshot. The helper writes protocol JSON only to stdout; diagnostics use stderr.

## Moonshine and native build integration

Use the official `moonshine-voice-macos-arm64.tar.gz` release archive already staged at `/tmp/voco-moonshine-native/native.tar.gz`. It contains `moonshine-c-api.h` and static `libmoonshine.a`, not the Swift `MicTranscriber` wrapper. Add a `CMoonshine` module map over the header and link the static library plus `c++`, Foundation, and CoreFoundation from the Swift helper. Keep the archive version pinned to v0.1.5 and verify its checksum in the build script. The official SwiftPM package source is useful API evidence, but its v0.1.5 XCFramework packaging is ambiguous for macOS, so the staged macOS C archive is the direct fit for the implementation baseline.

On setup-button press, call `moonshine_get_stt_dependencies("en", options:[model_arch="5"], ...)`, parse the returned manifest JSON, and download only the listed files into `~/Library/Application Support/Voco/Models/Moonshine/en-medium-streaming`. Never hardcode Moonshine filenames or CDN paths. Show per-file progress; verify the manifest's size and `crc32c` checksum before atomically moving each `.part` file into place. Cancellation can remove the active temporary file and retry can re-fetch it. Free manifest JSON with `moonshine_free_buffer()`.

Load with `moonshine_load_transcriber_from_files(modelRoot, MOONSHINE_MODEL_ARCH_MEDIUM_STREAMING, NULL, 0, MOONSHINE_HEADER_VERSION)`. The C API defines Medium Streaming as architecture 5. For each dictation session, create/start a stream, capture mono float PCM using the existing `AVAudioEngine` seam in `SpeechSession`, enqueue `moonshine_transcribe_add_audio_to_stream(...)` for each natural audio chunk, and call `moonshine_transcribe_stream(...)` on a serial worker around every 200–500 ms. The add-audio call only buffers PCM and is documented safe for frequent/time-critical capture calls; model inference belongs on the worker. Copy changed transcript lines before the next call on that transcriber, since the transcript view is owned by the transcriber until its next call. Use `is_updated` for partial UI changes and `is_complete` as the final-line boundary.

On hold release, stop the audio tap, call `moonshine_stop_stream`, then call `moonshine_transcribe_stream` once more to flush short trailing audio and mark all lines complete. Continuous mode can keep the existing energy-based `PauseGate`: after the configured quiet interval, stop and flush the current stream, insert completed lines, then start a fresh stream while leaving the engine capture active. Keep the session UUID and a copied `committedText` outside Moonshine because a fresh stream resets its transcript. This preserves the current configurable pause semantics and avoids feeding Moonshine partial hypotheses into final insertion.

`TextInsertion` and `LiveTextWriter` remain Swift-side. Capture the focused app before stopping or showing the pill, retain secure-field and focus-change checks, and keep pasteboard save/restore guarded by the pasteboard change count. The Electron renderer receives only transcript text and permission/model/dictation state. It never sends an AX element, PID, clipboard payload, audio buffer, or free-form native operation.

## Typed process contract

Use the Zod contract already drafted in `app/shared/protocol.ts`. Keep its current `AppState`, `Command`, and `NativeMessage` shapes as the shared source of truth. Native output is newline-delimited JSON over stdio. Commands carry IDs and receive `reply` messages; state changes publish full `state` snapshots; settings visibility uses `showSettings`. Keep helper logs on stderr.

The Electron preload exposes only `getState`, `command`, `subscribe`, and `closeSettings`. `ShortcutMonitor` emits hold/release/escape/continuous actions inside Swift; renderer key events never start global dictation. The helper captures `FocusTarget` at shortcut press time and never accepts an AX target, PID, pasteboard payload, audio buffer, or arbitrary native operation from the renderer.

The existing protocol discriminates model state as `missing`, `downloading`, `loading`, `ready`, or `error`; session state as `idle`, `starting`, `listening`, `finishing`, or `recovery`; and permissions as microphone/accessibility/shortcut readiness. The coordinator is the only owner of those state transitions. Preferences remain in Electron main storage and are sent as one full `setPreferences` value to the helper.

## Existing behavior to carry over

`FocusTarget.capture()` currently records the frontmost external process before capture. `resolved()` waits briefly for the focused element, while `validate()` rejects changed focus and secure fields. `insert()` prefers an AX selected-text write only when it can verify the result, falls back to Command-V for web editors, and restores the old pasteboard only if another app has not changed it. Keep those checks inside Swift.

`DictationCoordinator` should own a session UUID to ignore late Moonshine callbacks after cancel/restart, current and completed transcript text, hold versus continuous mode, and recovery behavior. Keep transcript state in the helper and send plain text snapshots to the UI. Settings can remain in Electron's main process store and be sent as one complete preference value at startup/change; do not persist duplicate copies in Swift `UserDefaults`.

## Material risks and early gates

1. **TCC identity and signing.** The Swift helper is a separate executable, but global event taps/Accessibility and microphone access are permissioned macOS operations. Bundle it under the signed Voco app, sign nested code with a stable identity, include microphone usage text in the packaged app, and test the first-run permission flow in both development and packaged builds. Accessibility may identify the helper separately from the Electron app; design setup around the actual permission owner the spike reports.
2. **Binary architecture.** The staged official C++ archive is macOS arm64. If Intel macOS must be supported, build the Moonshine C library for x86_64 from the upstream source or obtain a matching release artifact before shipping a universal app. The v0.1.5 SwiftPM package is an alternative, but verify its packaged macOS slices with a real link build first.
3. **Capture and flush ordering.** Audio tap buffers and C API stream calls must be serialized so the final audio chunk cannot race `moonshine_stop_stream`. On stop, drain queued PCM, stop the stream, then synchronously fetch the final transcript before emitting the completed snapshot.
4. **Pause semantics.** Keep the existing `PauseGate` energy threshold and `pauseSeconds` setting. When quiet expires, stop and flush the current stream, commit only complete lines, then start a fresh stream while keeping the microphone engine running. This uses Moonshine's documented stop/start support for discontinuous streams and preserves Voco's current pause behavior.

## Evidence

- [Moonshine model catalog](https://moonshine-voice.readthedocs.io/en/latest/models/available-models/) lists English Medium Streaming and its MIT license.
- [Moonshine C API](https://moonshine-voice.readthedocs.io/en/latest/api/c-api/) documents the model manifest, architecture constant, file-based loader, PCM streaming calls, transcript line flags, and buffer lifetime.
- [Official Swift package v0.1.5 manifest](https://github.com/moonshine-ai/moonshine-swift/blob/v0.1.5/Package.swift) and [package README](https://github.com/moonshine-ai/moonshine-swift) document the current packaging caveat.
- [Official macOS C++ archive instructions](https://github.com/moonshine-ai/moonshine/blob/main/examples/c%2B%2B/README.md) document the macOS arm64 static library fallback and explain that the C++ binding does not include microphone capture or downloading.
