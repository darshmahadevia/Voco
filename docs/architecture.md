# Architecture

Voco is one Rust executable. egui/eframe renders the dashboard. AppKit and Accessibility bindings implement macOS behavior. CPAL captures microphone audio. Native inference dependencies provide Moonshine, ONNX Runtime, and whisper.cpp. There is no web renderer or helper process.

## Ownership

`domain.rs` defines speech model IDs, output modes, capture modes, and session states. `gesture.rs` maps Fn, Space, modifier, and key events to hold, release, continuous-toggle, and cancellation actions.

`controller.rs` owns settings, the active session, the original focus target, the recorder, inference requests, model switching, downloads, and retained transcripts. The UI thread alone commits recognized text to a destination. A generation ID invalidates cancelled sessions and rejects late results. Model loads are serialized so the displayed model and active runtime cannot diverge.

`speech.rs` loads and transcribes all three engines on one inference worker. Whisper uses Metal. Moonshine and Parakeet share the statically linked ONNX Runtime. Cancellation aborts Whisper, checks Moonshine between audio chunks, and discards cancelled Parakeet results after inference completes.

`models.rs` owns pinned asset inventories, download progress, cancellation, checksum verification, installation locking, and atomic publication. Existing Moonshine and Whisper caches retain their paths. Parakeet ONNX uses a separate directory from the previous Swift CoreML runtime.

`audio.rs` captures the default microphone, downmixes to mono, and resamples to 16 kHz with a low-pass filter. Its bounded memory buffer holds at most ten minutes. Capture errors stop the session. Reaching the limit finishes recognition of the captured prefix.

`platform.rs` owns permissions, the global event tap, clipboard access, focus validation, insertion, and a nonactivating AppKit recording panel. The event tap runs on its own run loop and sends actions to the controller. It performs no Accessibility work in its callback.

`ui.rs` owns dashboard navigation, the practice field, settings controls, statistics, in-memory transcript views, tray menus, and screenshot verification. The practice field applies validated results directly to egui text state. Other apps receive a verified Accessibility write or clipboard-preserving paste.

`storage.rs` owns preferences migration and atomic settings persistence. The serialized shape contains preferences and usage totals. It has no audio or transcript fields.

## Dictation

Fn press captures the focused process, field, selection, and readable value. A 140 millisecond hold starts capture. Quick release cancels the pending hold. Fn + Space promotes a hold to continuous capture or toggles continuous capture. Fn release does not stop continuous capture. Escape invalidates the session and signals inference cancellation.

After capture stops, the worker returns a final transcript tagged with the session generation. The controller discards stale results, applies cleanup, waits briefly for shortcut modifiers to settle, and revalidates the destination before insertion. An uncertain or partial insertion is never retried automatically. Recovery keeps the complete text available for copying.

## Cleanup

Fast returns the raw transcript. Balanced uses Rust token and source-range rules. It preserves protected literals and line endings. Accurate currently uses Balanced and reports that FoundationModels formatting is unavailable. No cloud fallback exists.

The previous architecture is preserved as historical material under `docs/migration`. Current development commands are in [development.md](development.md).
