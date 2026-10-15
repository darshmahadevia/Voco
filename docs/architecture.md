# Voco desktop architecture

The current app is Electron with a React, TypeScript, and Motion interface. Electron main owns windows, the menu-bar icon, and the lifetime of a bundled macOS helper. The helper owns the selected local speech engine, audio capture, permissions, global shortcuts, session identity, and safe text insertion.

The renderer uses a narrow preload API to read state and send validated commands. It receives no audio buffers or filesystem access. Native model downloads begin only after an explicit **Download** action in setup or Settings. Setup requires one downloaded and successfully loaded model. Models stay in Application Support across app updates.

The shared state and command contract lives in `app/shared/protocol.ts`. The native coordinator publishes complete snapshots. The model catalog contains Moonshine Medium Streaming, Parakeet TDT 0.6B v2, and Whisper Large v3 Turbo. Each model has its own install state. `selectedModel` identifies the active engine, while `model` describes its runtime readiness. An inactive model can be installed without being loaded. Native code validates selection, loads the new engine, and persists the choice only after success. Switching unloads the current engine before loading the next to limit memory use. If loading fails, native code reloads the previous engine and keeps its saved selection.

`SpeechEngine` adapts Moonshine streaming audio input, FluidAudio CoreML inference, and whisper.cpp Metal inference to the same capture and final-transcript contract. It exposes asynchronous loading and finalization; there is no partial-transcript polling API. File and microphone diagnostics use those same methods. Parakeet loads verified CoreML assets directly without FluidAudio download helpers. Downloads verify pinned file sizes and checksums before replacing an installed model. Recognition never initiates a download.

Model state, permission state, and dictation state remain separate. A granted Keyboard access permission can coexist with an unavailable shortcut monitor and therefore needs a restart action.

Dictation captures audio while Fn / Globe is held and does not poll provisional transcripts or write into the editor. Moonshine accepts audio through its native streaming runtime; Parakeet and Whisper accumulate samples for their final inference. Releasing the key stops the microphone, drains accepted audio, and calls the selected engine's asynchronous `finish`. The pill stays visible in the finishing state until transcription and insertion complete.

The coordinator joins all final lines into one transcript and inserts it once through `FocusTarget.insert`. Incomplete final lines go to recovery together without inserting a partial prefix. The focus boundary rejects password fields, changed apps or fields, and held modifiers. The paste uses the current cursor or selection in the original field, including cursor movement during capture or processing. Writable native fields receive Accessibility insertion. Web and Electron fields receive a clipboard-preserving paste so their input handlers receive the complete text. Voco does not submit the field or press Return.

Session IDs reject late recognition results after cancellation. One insertion task handles the final transcript; Escape cancels that task before any unposted paste and invalidates the session. A paste already delivered to the destination cannot be recalled. Recognition failures leave the editor untouched, and insertion failures retain the final transcript for recovery even when optional transcript retention is disabled.

Ordinary pill updates contain status, not transcript previews. Recovery contains copyable words. Transcript retention is memory-only. A platform-specific helper can later replace the macOS helper while preserving the Electron interface and the process contract.

See [the migration design and alternatives](migration/architecture.md). [The predecessor architecture](migration/pre-electron-architecture.md) records the original Apple SpeechAnalyzer implementation and its insertion/permission fixes.

The listening protocol carries capture status without an insertion mode or partial transcript text. Microphone levels update the waveform independently of recognition. `lastTranscript` updates only when a final transcript arrives and its in-memory preference is enabled.

All macOS integration code lives in `native/Sources`. Direct focus and insertion fixtures live in `native/Tests` and exercise the same files compiled into the helper. `Sources/VocoCore` contains the hold and continuous shortcut gesture, with portable tests in `Tests/VocoCoreTests`. The predecessor SwiftUI application and its separate lifecycle checks have been removed.

## Transcript cleanup

`TranscriptPolisher` is a native adapter between final recognition and insertion. The `OutputMode` captured at session creation selects the original text, deterministic cleanup, or deterministic cleanup followed by FoundationModels formatting. A fresh language-model session prevents cross-dictation context retention. Protected spans keep literal text out of rule edits. Generated text must preserve the cleaned word sequence, protected spans, quantities, and line boundaries. The renderer receives availability, fallback notices, and optionally the latest raw transcript. It does not own an inference runtime.

The native adapter was chosen over an Electron-owned model runtime because native code already owns session cancellation, focus, and insertion. An Electron runtime would add a model distribution and lifecycle system plus another request protocol. The current choice depends on Apple Intelligence availability, with Balanced cleanup as the fallback when formatting is unavailable.
