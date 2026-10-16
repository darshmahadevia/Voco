# Voco

<!-- impeccable:product-schema 1 -->

## Platform

macOS

Rust desktop application for Apple Silicon Macs running macOS 26 or newer.

## Stack

Rust and egui/eframe provide the dashboard. Rust bindings to AppKit and Accessibility own system integration. CPAL captures audio. Statically linked inference libraries run Moonshine Medium Streaming, Parakeet TDT 0.6B v2 ONNX, and Whisper Large v3 Turbo in English.

## Product purpose

Dictate English directly into the text field you are using. Hold Fn or Globe to dictate and release to finish. Fn + Space toggles continuous capture. Escape cancels capture or pending transcription. A floating pill shows microphone status without taking typing focus.

## Capabilities and constraints

- Free to build and use, with MIT-licensed application code in a private repository. Speech models run locally. Preserve the license notices for each engine and model.
- Install the app first, then explicitly download and load a speech model in setup. Switch models while dictation is idle.
- Show download progress, cancellation, retry, loading, and readiness. Keep the model outside the app bundle so updates preserve it.
- Run speech recognition offline after setup, without an account, cloud service, API key, or subscription.
- Keep microphone capture and safe system text insertion in Rust. Reveal the Voco app when manual keyboard permission is needed.
- Record while listening, then insert the completed transcript once after hold release or continuous stop. Do not insert provisional words or revise earlier output.
- Use the current caret or selection in the original field. Refuse insertion if the app or field changes. Verify complete writes where the field exposes text and selection; retain the full transcript if insertion fails, without retrying a partial write.
- Show the microphone waveform during capture and Transcribing while recognition finishes. Keep the pill from taking typing focus.
- Retain recovery words for manual copying. Keep optional recent transcripts in memory until quit. Do not persist audio or transcript history.
- Start in the menu bar with the dashboard hidden. Closing the dashboard keeps dictation running. Provide a compact dashboard with readiness, Fn / Globe guidance, and recent transcripts held in memory. Use #0A0A0A for main backgrounds, graphite only on small controls and fields, fully rounded soft-white primary controls, restrained #FF742F orange voice accents, and bundled Manrope throughout. Home pairs a personal greeting with compact shortcut guidance and decorative ASCII voice artwork, followed by flat statistics and complete transcript rows. A persistent live footer keeps status and recovery available across pages. Settings shows one of four tab panels at a time, with segmented output choices and detailed guidance behind disclosures. Provide purposeful motion and reduced-motion support. First-run onboarding guides welcome, model download, microphone and keyboard access, and practice dictation with Fn / Globe troubleshooting. Keep model, access, shortcut, and transcript controls in Settings.
- Do not submit forms, press Return, or write to password fields.

## Output quality

Settings exposes Fast for the original speech-model transcript, Balanced for local filler and restart rules with punctuation repair, and Accurate for Balanced cleanup with a notice that FoundationModels formatting is unavailable in the Rust build. Speech-model choice stays independent. Accurate currently keeps Balanced cleanup because FoundationModels is a Swift-only API. Protect quotes, code, links, quantities, and line boundaries. Retain the latest original in memory only while transcript retention is enabled. Show Polishing during cleanup. The product prioritizes local processing and recoverable text, without a guarantee of accuracy or speed.

## Deferred work

Windows integration, languages beyond English, public signing/notarization, and additional product features.
