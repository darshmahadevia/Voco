# Voco migration candidate B: Electron session owner + Moonshine WASM worker

Historical document for an earlier Voco implementation. Commands and design details below may refer to removed code. See the [current README](../../README.md), [architecture](../architecture.md), and [development guide](../development.md).

## Grounded behavior

The current app is a native menu-bar dictation tool. `AppModel` owns setup and permissions, press/hold/release/cancel state, continuous mode, pause/commit behavior, prepared/active session identity, recovery text, and calls into the writer. `SpeechSession` owns AVFoundation audio capture, Apple SpeechAnalyzer/SpeechTranscriber, and finalization. `ShortcutMonitor` watches Fn/Globe, Fn+Space, Escape, and configured Option keys. `FocusTarget`, `LiveTextWriter`, and `VocoCore.LiveTextBuffer` protect the original document/caret and edit only the text range Voco inserted. The UI is the settings/setup window plus a non-activating microphone pill. See `docs/architecture.md` and `DESIGN.md`.

The migration must preserve these behavioral boundaries: a session ID fences late callbacks; a held shortcut starts capture only after its debounce; Fn+Space toggles continuous listening; partial hypotheses can be revised, final lines can be committed, and pause settling must not stop the microphone; Escape preserves already-written words; focus/document/caret changes stop automatic edits; failures retain copyable recovery text. Do not expose ordinary partial transcript text in the status pill.

## Shape

```text
Electron main (AppController)
  ├── settings window: React + TypeScript + Motion
  ├── non-activating status pill: React + TypeScript + Motion
  ├── Swift native helper process
  │     ├── global shortcuts and permission state
  │     ├── microphone capture -> bounded PCM frames
  │     └── focus snapshot + safe insertion / recovery copy
  └── hidden persistent renderer -> dedicated Web Worker
        └── @moonshine-ai/moonshine-wasm Transcriber (PCM input)
```

Electron main owns one `DictationSession` state machine per app instance and is the only authority allowed to accept shortcut events, allocate/finish a session ID, or publish app state. Keep the helper and Moonshine behind two main-process facades; renderer components only consume a typed snapshot and dispatch user commands. No transcript or audio buffer is persisted. Only session text needed for in-field writing and optional recovery is retained in memory/preferences according to the existing setting.

Use a persistent, hidden, sandboxed Electron renderer as the host for a dedicated Web Worker. This gives the current WASM binding a browser environment and durable Cache Storage for assets while keeping inference off the visible UI thread and independent of whether the settings window is open. Do not put `MicTranscriber` in this worker: it owns its own platform microphone. Use the low-level PCM-input `Transcriber`, because the Swift helper is the sole microphone capture owner. Feed mono `Float32Array` PCM chunks with their sample rate; use transferable buffers and a bounded queue so a slow inference callback cannot grow memory without limit. Main tags worker messages with `sessionId` and drops stale callbacks.

The helper should be a bundled Swift executable started as an Electron child process, with versioned, newline-delimited JSON control messages and a small length-prefixed binary PCM channel (or a separate local socket) to avoid base64. It keeps the macOS-only AppKit/Accessibility logic already in `ShortcutMonitor`, `FocusTarget`, and `LiveTextWriter`; it does not link or own a speech engine. Preserve one insertion owner: main sends the helper assembled transcript updates/commits, and the helper validates the captured target before applying edits. The helper reports shortcut transitions and permissions to main, never directly to React.

## Public TypeScript boundaries

```ts
type SessionId = string & { readonly __brand: "SessionId" };
type DictationPhase = "idle" | "starting" | "listening" | "finishing" | "recovery";
type AppSnapshot = {
  phase: DictationPhase;
  model: "missing" | "downloading" | "ready" | "failed";
  modelProgress?: { fraction?: number; file?: string };
  microphone: "unknown" | "denied" | "ready";
  accessibility: "unknown" | "denied" | "ready";
  continuous: boolean;
  recoveryText?: string;
};

type AppCommand =
  | { type: "model.download" }
  | { type: "permission.request"; permission: "microphone" | "accessibility" }
  | { type: "dictation.cancel" }
  | { type: "settings.update"; key: "talkKey" | "pauseSeconds" | "keepLastTranscript"; value: string | number | boolean }
  | { type: "recovery.copy" }
  | { type: "recovery.dismiss" };

interface VocoPreload {
  getSnapshot(): Promise<AppSnapshot>;
  dispatch(command: AppCommand): Promise<void>;
  subscribe(listener: (snapshot: AppSnapshot) => void): () => void;
}

type HelperCommand =
  | { type: "model.permissions.refresh" }
  | { type: "capture.start"; sessionId: SessionId; mode: "hold" | "continuous" }
  | { type: "capture.stop"; sessionId: SessionId }
  | { type: "capture.cancel"; sessionId: SessionId }
  | { type: "insert.update"; sessionId: SessionId; text: string; settledThrough?: number }
  | { type: "insert.finish"; sessionId: SessionId; text: string }
  | { type: "insert.copyRecovery"; text: string };

type HelperEvent =
  | { type: "permission.state"; microphone: AppSnapshot["microphone"]; accessibility: AppSnapshot["accessibility"] }
  | { type: "shortcut"; action: "pressed" | "released" | "cancelled" | "continuousToggle" }
  | { type: "capture.audio"; sessionId: SessionId; sequence: number; sampleRate: number; pcm: Float32Array }
  | { type: "capture.ended"; sessionId: SessionId }
  | { type: "helper.error"; sessionId?: SessionId; message: string };

type SpeechWorkerCommand =
  | { type: "model.load" }
  | { type: "session.start"; sessionId: SessionId }
  | { type: "session.audio"; sessionId: SessionId; sequence: number; sampleRate: number; pcm: Float32Array }
  | { type: "session.finish" | "session.cancel"; sessionId: SessionId };

type SpeechWorkerEvent =
  | { type: "model.progress"; fraction: number; file: string }
  | { type: "model.ready" }
  | { type: "model.failed"; message: string }
  | { type: "line.partial"; sessionId: SessionId; lineId: string; text: string }
  | { type: "line.final"; sessionId: SessionId; lineId: string; text: string; lastTranscriptionLatencyMs?: number }
  | { type: "session.finished" | "session.cancelled"; sessionId: SessionId }
  | { type: "speech.error"; sessionId?: SessionId; message: string };
```

The SDK's in-progress text is revisable; only completed lines are final. Keep these separate in `TranscriptAssembler` (the existing core model is a good behavioral reference). `DictationSession` consumes final-line and pause-settling events, controls the helper's safe writer, and emits a small `AppSnapshot`; the renderer never receives audio chunks.

Suggested main-process signatures:

```ts
class AppController {
  getSnapshot(): AppSnapshot;
  dispatch(command: AppCommand): Promise<void>;
  onHelperEvent(event: HelperEvent): void;
  onSpeechEvent(event: SpeechWorkerEvent): void;
}

class DictationSession {
  press(): void;
  release(): void;
  cancel(): void;
  toggleContinuous(): void;
  onPartial(lineId: string, text: string): void;
  onFinal(lineId: string, text: string): void;
}

interface NativeBridge {
  startCapture(sessionId: SessionId, mode: "hold" | "continuous"): Promise<void>;
  stopCapture(sessionId: SessionId): Promise<void>;
  cancelCapture(sessionId: SessionId): Promise<void>;
  updateInsertion(sessionId: SessionId, text: string, settledThrough?: number): Promise<void>;
  finishInsertion(sessionId: SessionId, text: string): Promise<void>;
}

interface SpeechEngine {
  load(onProgress: (fraction: number, file: string) => void): Promise<void>;
  start(sessionId: SessionId): Promise<void>;
  pushAudio(sessionId: SessionId, sequence: number, pcm: Float32Array, sampleRate: number): void;
  finish(sessionId: SessionId): Promise<void>;
  cancel(sessionId: SessionId): void;
}
```

Exact SDK adapter names should be confirmed against the pinned `@moonshine-ai/moonshine-wasm` version at implementation. The official current JavaScript quickstart supports `MicTranscriber` with `.modelArch(ModelArch.MediumStreaming)`, `.onText`, `.onLine`, `.onProgress`, then `load()` / `start()`. For externally captured PCM, the official transcription guide identifies low-level `Transcriber` as the path and documents feeding mono float PCM plus sample rate through `add_audio`; JavaScript uses camelCase binding names. The app should pin a tested SDK version and lock the model cache key/asset setup to it.

## Setup and model lifecycle

The first-run UI offers one explicit “Download speech model” action. It sends `model.download`; the worker constructs the English streaming transcriber, attaches the progress callback, and awaits `load()`. The SDK downloads missing browser assets into Cache Storage bucket `moonshine-models-v1`; subsequent launches reuse that cache offline. On successful load, persist only `model.ready` as an app preference; still validate by loading the model when starting the service after relaunch. A transient network/model error returns setup to a retryable state. Dictation starts only when model load and macOS microphone/accessibility requirements are ready.

Official docs say the English catalog default is Medium Streaming and show the explicit `ModelArch.MediumStreaming` setter. Model assets are downloaded on first `load()` and reused offline from Cache Storage in browser builds. The user-approved download screen therefore maps directly to the SDK's load/progress lifecycle. Do not promise browser-cache durability beyond the Electron app's own persistent profile; do not clear its storage on app updates.

## Feasibility / risk to prove early

The exact WASM package and lower-level PCM API must be smoke-tested inside the packaged Electron worker before replacing the native speech pipeline. Official docs establish both the Node package and PCM-fed `Transcriber` path, but do not explicitly document Electron's `utilityProcess` or Web Worker host. A worker-hosted renderer is the lower-risk fit because the JS binding's normal model cache is browser Cache Storage; main/utility-process-only inference would need a proven Node cache/runtime path. First spike: import the pinned package from the bundled worker, run `load()` from setup, restart offline, stream a real PCM fixture, and verify partial/final events. If worker WASM instantiation or model cache fails, move the SDK adapter to the persistent renderer thread as a contained fallback; keep the same `SpeechEngine` interface.

The helper's PCM bridge and the main process session state are new seams. Build them before removing the Swift UI so shortcut delivery, privacy permissions, and safe insertion remain independently testable. Existing `scripts/check-shortcut.sh`, `check-permissions.sh`, `verify-focused-insertion.sh`, `check-recovery.sh`, and `check-restart.sh` are useful behavioral acceptance references during migration.

## Difference from a Swift-owned design

This candidate keeps the Swift code strictly as a macOS integration helper and moves session policy to TypeScript. It keeps the helper small by sharing the current proven focus/insertion implementation, while Electron's main process becomes the authority for lifecycle and UI state. The cost is an audio IPC path and an Electron/WASM worker hosting spike. Compared with loading Moonshine's native static library in Swift, this gives the app one JavaScript inference adapter and a future seam for Windows, while accepting the extra bridge complexity.

## Official sources checked

- [Moonshine JavaScript quickstart](https://moonshine-voice.readthedocs.io/en/latest/quickstart/) — `@moonshine-ai/moonshine-wasm`, `MediumStreaming`, callbacks, `load()` and `start()`.
- [Moonshine model downloads](https://moonshine-voice.readthedocs.io/en/latest/using/downloading-models/) — browser Cache Storage bucket `moonshine-models-v1`, per-file progress, offline reuse, and Medium Streaming model assets.
- [Moonshine transcription guide](https://moonshine-voice.readthedocs.io/en/latest/using/transcription/) — partial versus final callbacks and external PCM input.
- [Moonshine API classes](https://moonshine-voice.readthedocs.io/en/latest/api/classes/) — `Transcriber`/`MicTranscriber` responsibilities and audio format.
