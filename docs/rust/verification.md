# Rust migration verification

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
