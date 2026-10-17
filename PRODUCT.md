# Voco

<!-- impeccable:product-schema 1 -->

## Platform

macOS

Rust desktop application for Apple Silicon Macs running macOS 26 or newer.

## Stack

Rust and GPUI provide the dashboard and floating recording pill. Native GPUI input components handle text editing and composition. Rust bindings to AppKit and Accessibility own system integration. CPAL captures audio. Statically linked inference libraries run Moonshine Medium Streaming, Parakeet TDT 0.6B v2 ONNX, and Whisper Large v3 Turbo in English.

## Product purpose

Dictate English directly into the text field you are using. Hold Fn or Globe to dictate and release to finish. Fn + Space toggles continuous capture. Escape cancels capture or pending transcription. A floating pill shows microphone status without taking typing focus.

## Capabilities and constraints

- Free to build and use, with MIT-licensed application code in a public repository. Speech models run locally. Preserve the license notices for each engine and model.
- Install the app first, then download a speech model in Settings. Switch models while dictation is idle.
- Show download progress, cancellation, retry, loading, and readiness. Keep the model outside the app bundle so updates preserve it.
- Run speech recognition offline after setup, without an account, cloud service, API key, or subscription.
- Keep microphone capture and safe system text insertion in Rust. Reveal the Voco app when manual keyboard permission is needed.
- Record while listening, then insert the completed transcript once after hold release or continuous stop. Do not insert provisional words or revise earlier output.
- Use the current caret or selection in the original field. Refuse insertion if the app or field changes. Verify complete writes where the field exposes text and selection; retain the full transcript if insertion fails, without retrying a partial write.
- Show the microphone waveform during capture and Transcribing while recognition finishes. Keep the pill from taking typing focus.
- Retain recovery words for manual copying. Keep optional recent transcripts in memory until quit. Do not persist audio or transcript history.
- Start in the menu bar with the dashboard hidden. Closing the dashboard keeps dictation running.
- Provide Home, Transcripts, Statistics, and Settings pages. Home has shortcut guidance, setup actions, usage totals, a practice field, and recent transcripts. Transcripts supports search and copying.
- Keep status and recovery visible below page scrolling. Settings has Output, Models, Access, and Dictation tabs.
- Use a black canvas, graphite controls, soft-white primary buttons, orange voice details, and bundled Manrope. Follow [DESIGN.md](DESIGN.md) for colors, typography, spacing, and reduced-motion behavior.
- Do not submit forms, press Return, or write to password fields.

## Output quality

The speech model and output mode are separate choices.

- Fast returns the speech model's original transcript.
- Balanced removes fillers and spoken restarts with local rules and repairs punctuation. The rules protect quotes, code, links, quantities, and line boundaries.
- Accurate formats Balanced output with Apple's on-device FoundationModels, preserving words and protected literals. Unavailable models, failed or unsafe results, and an eight-second deadline fall back to Balanced output with a notice.

The app keeps the latest original transcript in memory only while transcript retention is enabled. Recognition and cleanup can make mistakes. Review the result before sending it.

## Deferred work

Windows integration, languages beyond English, public signing/notarization, and additional product features.
