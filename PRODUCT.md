# Voco

<!-- impeccable:product-schema 1 -->

## Platform

web

Electron desktop application for macOS and Apple Silicon. Windows follows after the macOS application is stable.

## Stack

Electron, React, TypeScript, and Motion provide the interface. A bundled Swift/AppKit/AVFoundation helper owns system integration and runs the pinned native Moonshine library. English Medium Streaming is the speech model.

## Product purpose

Dictate English directly into the text field you are using. Hold Fn or Globe to dictate and release to finish. A floating pill shows microphone status without taking typing focus.

## Capabilities and constraints

- Free to build and use, with open-source app code and an MIT-licensed English streaming model.
- Install the app first, then explicitly download Moonshine Medium Streaming in setup.
- Show download progress, cancellation, retry, loading, and readiness. Keep the model outside the app bundle so updates preserve it.
- Run speech recognition offline after setup, without an account, cloud service, API key, or subscription.
- Keep microphone capture and safe system text insertion in the native helper. Reveal the exact helper app when manual keyboard permission is needed.
- Revise only Voco's inserted text in supported native fields. Stop writing on a changed field, document, caret, or app.
- Favor a fast first response and rapid character bursts. Delay provisional words briefly, then insert stable text without revising earlier output. Stable short utterances appear before release. Use live keyboard input for readable web and Electron fields with writable selections. Buffer text in fields that reject live insertion and insert it on release.
- Retain recovery words for manual copying. Keep one optional last transcript in memory until quit. Do not persist audio or transcript history.
- Open to a wide dashboard with readiness, Fn / Globe guidance, and the optional latest transcript held in memory. Use black surfaces, gray borders, a restrained orange accent, bundled Manrope, a Pixelify Sans Home accent matching the first headline line in size, and Instrument Serif setup headlines, and reduced-motion support. First-run onboarding guides welcome, model download, microphone and keyboard access, and practice dictation with Fn / Globe troubleshooting. Keep model, access, shortcut, and transcript controls in Settings.
- Do not submit forms, press Return, or write to password fields.

## Deferred work

Windows integration, languages beyond English, public signing/notarization, and additional product features.
