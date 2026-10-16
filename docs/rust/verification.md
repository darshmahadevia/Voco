# Rust migration verification

This record describes the earlier egui port. The [GPUI verification record](../gpui/verification.md) covers the current native interface.

## Core and recognition

The original TypeScript application passed 28 tests and type checking before migration.

The first Rust core check passed 15 tests. These include all 49 cleanup fixtures, 52 cleanup examples extracted from the Swift checks, literal protection, unsafe-edit rejection, idempotence, shortcut gestures, model integrity and cancellation, atomic model publication, usage statistics, and transcript-free settings storage.

All three engines transcribed the same local mono 16 kHz recording. The phrase was generated for earlier Voco verification and was already present at `/tmp/voco-audit-phrase.wav`.

- Moonshine returned `The quick brown fox jumps over the lazy dog, this is a local speech recognition test.`
- Whisper returned `the quick brown fox jumps over the lazy dog. This is a local speech recognition test.`
- Parakeet returned `The quick brown fox jumps over the lazy dog. This is a local speech recognition test.`

Active cancellation followed by reuse passed for each engine. Whisper aborts through its native callback. Moonshine checks between chunks. Parakeet finishes ongoing inference and discards a cancelled result because its Rust runtime has no abort API.

A real network download cancelled at one percent and left no installed model or staging directory. The installer also passed corruption and interrupted-verification tests.

The linked inference executable uses only Apple frameworks and system dynamic libraries. Moonshine, ONNX Runtime, Whisper, and ggml are statically linked. Whisper uses its embedded Metal library.

## Desktop checks

The first integrated run passed 22 Rust tests. The executable created its tray icon and rendered Home, Transcripts, Stats, and Settings to four screenshots in `/tmp/voco-rust-ui`.

The runtime reported Accessibility granted, a running keyboard monitor, and microphone permission absent for the new executable. This does not prove live microphone capture or physical Fn key behavior.

## Known differences

The Rust dashboard uses egui and the recording indicator uses an AppKit panel created through Rust bindings. It is not pixel-identical to the old browser UI.

Accurate cleanup uses Balanced cleanup and displays a notice. The Swift-only FoundationModels formatting pass is unavailable.

The Parakeet runtime uses a separately downloaded int8 ONNX export of TDT 0.6B v2. Existing Moonshine and Whisper caches are reused. The old CoreML Parakeet cache remains on disk and is not modified.

## Final native and build checks

The integrated verification command passed formatting, Clippy with warnings denied, 34 tests, and the executable build. The seven original Swift shortcut tests are now Rust tests.

`voco --verify-insertion` passed against disposable native text fields. It inserted 2,200 UTF-16 units containing emoji, accented text, Japanese text, and line breaks. Selection replacement, changed-selection refusal, changed-field refusal, and password-field refusal all passed. Clipboard unit tests preserved every representation and preserved a new user copy made during insertion.

The native adapter's isolated checks exercised synthetic Fn, Fn+Space, Escape, and event-tap retry. Physical keyboard presses across Spaces and fullscreen apps remain unverified. Browser-editor paste compatibility is implemented but has not been checked live.

The optimized app bundle passed code-signature verification and a contents/dependency audit. It has one Rust executable, static inference dependencies, system dynamic dependencies, and no Electron, JavaScript, HTML, or Swift application files.

The final four-page screenshot run is under `/tmp/voco-rust-packaged-ui`. The regular-weight font corrected the overly light first rendering. `docs/rust/ui.md` records the UI choices. The existing `.impeccable/design.json` sidecar predates DESIGN.md; it was not refreshed during the port.

The requested Claude and Grok review providers were disabled. Independent design and code reviews used separate Codex tasks. A review from another model family was unavailable.

## Durable evidence and review corrections

The baseline source is available at commit `0d264a6`, including `app/shared/protocol.test.ts`. That source was removed from the current tree after the Rust replacement passed its checks.

The committed result artifacts are [inference.txt](evidence/inference.txt), [insertion.json](evidence/insertion.json), and [ui.json](evidence/ui.json). The insertion report includes live assertions that the recording panel cannot become key or main, ignores mouse input, and preserves the editor's keyboard focus.

The real UI check initially failed because the egui practice field's Accessibility tree was unavailable. The fix captures the field's value and Unicode character selection directly from egui, checks that both remain unchanged, and applies the replacement through egui text state. The revised four-page executable check replaced a selected emoji with `Rust` and exited successfully. This verifies the shared field helpers and actual UI state; it does not exercise microphone capture or the complete dictation controller.

Practice insertion rejects pending text, key, clipboard, IME, and pointer-selection input before committing a result. Active IME composition and selection drags also block insertion. The final focused review found this additional input race, which the final guard addresses.

Both debug and release Whisper native objects were checked with `otool` and target macOS 26.0. Existing cached objects had targeted the host's macOS 27 until the native build cache was rebuilt with the pinned deployment target.

The final UI check also closes the dashboard through a real window-close event, verifies the native window is hidden, launches a second executable with `--show`, and verifies the native window becomes visible again. The final release app was checked separately from the debug executable.

The source and bundle audits found no remaining Swift, TypeScript, JavaScript, HTML, Electron, or helper application files in the tracked application or packaged runtime. Shell scripts handle development, verification, packaging, and installation.
