# Voco

<!-- impeccable:product-schema 1 -->

## Platform

Native macOS. Apple Silicon, macOS 26 or newer.

## Stack

Swift, SwiftUI, and AppKit. Apple SpeechAnalyzer and SpeechTranscriber provide local recognition. Swift Package Manager builds the app without external dependencies. This stack follows the user's choice of Apple's on-device engine.

## Product purpose

Dictate English directly into the text field you are using. Hold Fn or Globe to write live words and release to stop. Fn + Space toggles continuous listening and settles phrases after pauses. A minimal microphone pill sits at the bottom center of the active display.

## Capabilities and constraints

- Free to build and use. Open-source application code.
- Apple supplies the proprietary speech model. The user accepted this for the first version.
- English only initially. Fn or Globe is the default trigger.
- Write provisional results into the target field and safely revise only Voco's inserted range. Show microphone status in the pill, with text only in recovery.
- No account, cloud transcription service, or subscription.
- Download speech assets during initial setup. Capture audio during a key hold or an explicitly toggled continuous session.
- Whispered speech support is outside the first version.
- Retain the transcript for manual copying when automatic insertion is unavailable.
- If live editing is unsupported, buffer text until release or a pause and indicate that mode.

## Open decisions

Public distribution and signing are deferred. The app is named Voco.
