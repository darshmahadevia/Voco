# Architecture

Voco is one Rust executable. GPUI renders the dashboard and floating recording pill using Metal. AppKit and Accessibility bindings implement macOS behavior. CPAL captures microphone audio. Native inference dependencies provide Moonshine, ONNX Runtime, and whisper.cpp. There is no web renderer or helper process.

## Ownership

`domain.rs` defines speech model IDs, output modes, capture modes, and session states. `gesture.rs` maps Fn, Space, modifier, and key events to hold, release, continuous-toggle, and cancellation actions.

`controller.rs` owns settings, the active session, the original focus target, the recorder, inference requests, model switching, downloads, and retained transcripts. The UI thread alone commits recognized text to a destination. A generation ID invalidates cancelled sessions and rejects late results. Model loads are serialized so the displayed model and active runtime cannot diverge.

`speech.rs` loads and transcribes all three engines on one inference worker. Whisper uses Metal. Moonshine and Parakeet share the statically linked ONNX Runtime. Cancellation aborts Whisper, checks Moonshine between audio chunks, and discards cancelled Parakeet results after inference completes.

`models.rs` owns pinned asset inventories, download progress, cancellation, checksum verification, installation locking, and atomic publication. Existing Moonshine and Whisper caches retain their paths. Parakeet ONNX uses a separate directory from the previous Swift CoreML runtime.

`audio.rs` captures the default microphone, downmixes to mono, and resamples to 16 kHz with a low-pass filter. Its bounded memory buffer holds at most ten minutes. Capture errors stop the session. Reaching the limit finishes recognition of the captured prefix.

`platform.rs` owns permissions, the global event tap, clipboard access, focus validation, insertion, and macOS window integration. The event tap runs on its own run loop and sends actions to the controller. It performs no Accessibility work in its callback.

`ui.rs` owns dashboard navigation, the practice field, settings controls, statistics, in-memory transcript views, tray menus, and screenshot verification. The practice field applies validated results to its native GPUI input state, converting UTF-16 selections into character-based ranges and cursor positions. Other apps receive a verified Accessibility write or clipboard-preserving paste.

`overlay.rs` draws the voice pill in GPUI. Its macOS panel cannot become key or main and ignores pointer input. It shows measured microphone energy during listening and a separate progress indicator during transcription.

`storage.rs` owns preferences migration and atomic settings persistence. The serialized shape contains preferences and usage totals. It has no audio or transcript fields.

## Dictation

Fn press captures the focused process, field, selection, and readable value. A 140 millisecond hold starts capture. Quick release cancels the pending hold. Fn + Space promotes a hold to continuous capture or toggles continuous capture. Fn release does not stop continuous capture. Escape invalidates the session and signals inference cancellation.

After capture stops, the worker transcribes and applies the frozen output mode, then returns the raw transcript, cleaned text, and notice tagged with the session generation. The controller discards stale results, waits briefly for shortcut modifiers to settle, and revalidates the destination before insertion. An uncertain or partial insertion is never retried automatically. Recovery keeps the complete text available for copying.

External target capture enables Electron Accessibility once, then retries unavailable focus for up to 300 ms, plus any in-flight Accessibility call. Capture stays on the original app and stops if permission or app focus changes. Later insertion checks read focus without enabling Accessibility again.

## Cleanup

Fast returns the raw transcript. Balanced uses Rust token and source-range rules. It preserves protected literals and line endings. Accurate formats Balanced output through `native/FoundationFormatting.swift`, a small C ABI bridge statically linked into the Rust executable. The bridge uses Apple's on-device FoundationModels with the original structured response and prompt. Rust validates word order, case-sensitive names, quantities, protected literals, symbols, and line breaks before accepting output. Formatting runs on the inference worker with an eight-second deadline and a 2,000-byte input limit. Generation IDs discard results after cancellation. Failures keep Balanced output with a notice. No cloud fallback exists.

The previous architecture is preserved as historical material under `docs/migration`. Current development commands are in [development.md](development.md).
