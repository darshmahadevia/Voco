# Voco

<!-- impeccable:product-schema 1 -->

## Platform

web

Electron desktop application for Apple Silicon Macs running macOS 26 or newer.

## Stack

Electron, React, TypeScript, and Motion provide the interface. A bundled Swift/AppKit/AVFoundation helper owns system integration and local recognition. Users choose Moonshine Medium Streaming, Parakeet TDT 0.6B v2, or Whisper Large v3 Turbo. All run in English mode.

## Product purpose

Dictate English directly into the text field you are using. Hold Fn or Globe to dictate and release to finish. Fn + Space toggles continuous capture. Escape cancels capture or pending transcription. A floating pill shows microphone status without taking typing focus.

## Capabilities and constraints

- Free to build and use, with open-source app code and local speech models. Preserve the license notices for each engine and model.
- Install the app first, then explicitly download and load a speech model in setup. Switch models while dictation is idle.
- Show download progress, cancellation, retry, loading, and readiness. Keep the model outside the app bundle so updates preserve it.
- Run speech recognition offline after setup, without an account, cloud service, API key, or subscription.
- Keep microphone capture and safe system text insertion in the native helper. Reveal the exact helper app when manual keyboard permission is needed.
- Record while listening, then insert the completed transcript once after hold release or continuous stop. Do not insert provisional words or revise earlier output.
- Use the current caret or selection in the original field. Refuse insertion if the app or field changes. Verify complete writes where the field exposes text and selection; retain the full transcript if insertion fails, without retrying a partial write.
- Show the microphone waveform during capture and Transcribing while recognition finishes. Keep the pill from taking typing focus.
- Retain recovery words for manual copying. Keep optional recent transcripts in memory until quit. Do not persist audio or transcript history.
- Start in the menu bar with the dashboard hidden. Closing the dashboard keeps dictation running. Provide a compact dashboard with readiness, Fn / Globe guidance, and recent transcripts held in memory. Use dark graphite surfaces, tonal layering, fully rounded soft-white primary controls, restrained orange voice accents, and bundled Manrope throughout. Home pairs a personal greeting with compact shortcut guidance, followed by flat statistics and complete transcript rows. A persistent live footer keeps status and recovery available across pages. Settings has a section index and segmented output choices. Provide purposeful motion and reduced-motion support. First-run onboarding guides welcome, model download, microphone and keyboard access, and practice dictation with Fn / Globe troubleshooting. Keep model, access, shortcut, and transcript controls in Settings.
- Do not submit forms, press Return, or write to password fields.

## Output quality

Settings exposes Fast for the original speech-model transcript, Balanced for local filler and restart rules with punctuation repair, and Accurate for an optional on-device FoundationModels cleanup pass. Speech-model choice stays independent. Accurate starts with Balanced cleanup and keeps that cleanup if AI formatting is unavailable or fails validation. Protect quotes, code, links, quantities, and line boundaries. Retain the latest original in memory only while transcript retention is enabled. Show Polishing during cleanup. The product prioritizes local processing and recoverable text, without a guarantee of accuracy or speed.

## Deferred work

Windows integration, languages beyond English, public signing/notarization, and additional product features.
