# Electron migration architecture

Historical document for an earlier Voco implementation. Commands and design details below may refer to removed code. See the [current README](../../README.md), [architecture](../architecture.md), and [development guide](../development.md).

Voco's desktop interface moves to Electron, React, TypeScript, and Motion. A bundled macOS helper owns Moonshine Medium Streaming recognition, microphone capture, global shortcuts, and safe text insertion. Windows is deferred until the macOS app is stable.

## Caller experience

Run `npm install` and `npm run dev` to open setup. Install the model with **Download speech model**, then grant microphone and keyboard access. Close settings and hold Fn or Globe in another app's text field. Fn / Globe hold-to-talk is the only mode.

React reads `window.voco.getState()`, subscribes through `window.voco.subscribe()`, and submits a typed command through `window.voco.command()`. The preload exposes no filesystem, process, arbitrary IPC channel, or network API.

## State ownership

`app/shared/protocol.ts` defines model readiness, permissions, preferences, dictation status, and recovery as schema-derived TypeScript values. Electron validates every native event and every renderer command. The helper owns the authoritative state. Settings and the nonactivating pill consume snapshots.

Electron main owns windows, the tray, and the helper's process lifetime. Native inference and insertion stay together, so audio never crosses into a renderer. Native session IDs reject stale recognition callbacks. Provisional recognition and final lines have separate identities, preventing release from reinserting already committed words.

## Synthesis decision

The native candidate is the base. The independent design judge preferred it for safe insertion and fewer process boundaries. The worker candidate contributed explicit stale-event protection and real inference plus offline-restart verification. Its PCM transport, hidden renderer, worker lifecycle, and browser model cache are unnecessary for the first macOS release.

The native library is an early build gate. Moonshine's Swift package documents an XCFramework packaging caveat; the official macOS ARM64 C API archive is the supported fallback. The build pins a library release and verifies its checksum. No Python installation is required by the shipped app.

## Accepted tradeoffs

- macOS and Apple Silicon ship first. Windows needs a new native adapter, while Electron can reuse the interface and state contract.
- The bundled helper runs under the desktop app’s permission identity. Standalone helper checks require a separate grant.
- A model download follows explicit user consent during setup. The model lives outside the app bundle and survives updates.
- Local packaging uses a persistent development certificate when configured, otherwise ad-hoc signing. Public Developer ID signing and notarization remain separate distribution work.

## Verification gates

Run the existing core and focus/insertion checks before changing the native integration. Build the native helper, exercise its actual JSON protocol without permissions, download the real Medium Streaming assets, and transcribe a local audio fixture. Relaunch with the model cached and verify no network download occurs. Inspect the running React setup and pill, then package the app and verify its helper executable and process lifetime.

Physical microphone capture and keyboard grants depend on macOS permission settings. Automated fixture transcription does not prove either.
