# Voco

Local English dictation for Apple Silicon Macs running macOS 26 or newer, with optional on-device transcript cleanup. Hold Fn or Globe to speak, then release to transcribe and insert the complete text into the focused app. Press Fn + Space to start continuous capture and press it again to stop. Escape cancels capture or pending transcription.

Electron, React, TypeScript, and Vite provide the interface. A bundled Swift helper handles microphone capture, global shortcuts, local recognition, and text insertion. Moonshine, Parakeet, and Whisper run on this Mac without an account or transcription API key.

## Build and install

Development requires Node.js 22 or newer, Swift 6.2 or newer from Xcode Command Line Tools, and CMake. The build also uses Apple's `codesign`, `iconutil`, `plutil`, and `xcrun` CLIs. Set `VOCO_CMAKE` to a CMake executable if it is outside `PATH`. The build also recognizes the existing `~/Library/Caches/Voco/BuildTools/cmake/bin/cmake` installation.

```sh
npm ci
npm run dev
```

The dev command clears `ELECTRON_RUN_AS_NODE` so shells used by coding tools cannot accidentally launch Electron as Node. `npm run dev:ui` opens a renderer preview with example state; use the Electron app for native actions.

To build and install the desktop app:

```sh
./scripts/install.sh
open ~/Applications/Voco.app
```

`npm run build` builds the Swift helper and production interface. `npm run pack` creates the signed app bundle, and `npm run dist` creates a disk image. `npm run build:icons` regenerates the icon from the committed brand PNG when needed.

Native dependencies are pinned to Moonshine 0.1.5, FluidAudio 0.9.1, and whisper.cpp 1.9.5. The build verifies the Moonshine archive checksum and Whisper source revision. It does not download speech models. Native artifacts live in `~/Library/Caches/Voco/Native`, with `native/build` linking there. Set `VOCO_NATIVE_BUILD_DIR` to choose another cache. Desktop artifacts live in `~/Library/Caches/Voco/Electron`, with `release` linking there. Installation keeps one app at `~/Applications/Voco.app` and moves the previous bundle to Trash.

## Set up dictation

1. Open Voco's menu bar menu and choose **Open Dashboard**. The dashboard stays hidden at startup and closing it keeps dictation running.
2. Choose **Set up Voco**, then download a speech model. Setup requires an installed model that loads successfully. Settings lets you download another model or choose **Use model** for one already installed. Switch models while dictation is idle.
3. Allow Microphone and Keyboard access. Keyboard access uses macOS Accessibility, named **Device Control and Data Access** on this Mac running macOS 27. If access is granted but the shortcut monitor is unavailable, use **Restart Voco**.
4. In macOS Keyboard settings, set **Press Globe key to** to **Do Nothing** and keep Apple Dictation on a separate shortcut.
5. Try the practice field, then focus a text field in another app and hold Fn or Globe to speak.

Models live under `~/Library/Application Support/Voco/models`, outside the app bundle. The active choice persists across restarts. Downloads show progress and support cancellation and retry. A missing or damaged model reports a repairable error; recognition never starts a hidden download. Once installed, recognition works offline.

The current models are Moonshine Medium Streaming, Parakeet TDT 0.6B v2, and Whisper Large v3 Turbo. All use English dictation. Whisper's multilingual weights run in English mode.

## Output quality

Settings offers **Fast**, **Balanced**, and **Accurate**. Fast keeps the speech model's words. Balanced removes fillers and spoken restarts, tidies their punctuation, and protects literal text. Accurate adds Apple's on-device model for formatting when Apple Intelligence is available, and keeps Balanced cleanup if formatting fails. The speech model is selected separately. These options do not promise error-free recognition or a measured accuracy ranking.

With transcript retention enabled, Home lets you inspect and copy the original when cleanup changes it. See [output modes, examples, and evaluation guidance](docs/local-dictation.md).

## Insertion and privacy

Voco records while listening and inserts once after transcription finishes. The pill shows the microphone waveform during capture and **Transcribing** afterward. The pill shows **Polishing** during optional cleanup. No provisional words are written into the destination.

The insertion uses the current caret or selection in the original field. Selected text is replaced, as with ordinary typing. Switching apps or fields prevents insertion and retains the completed transcript for copying. Password fields are rejected. Native text controls use Accessibility writes; browser and Electron controls receive a paste event so their application state updates too. For fields that expose readable text and selection, Voco verifies the complete write. Incomplete writes report failure and retain the full transcript without retrying and duplicating the partial text. Paste restores the previous clipboard unless another app changes it. Voco never presses Return or submits a form.

Transcripts stay in memory until you quit. Turning off **Keep last transcript** clears retained text. Audio and transcript history are not written to disk. Usage totals and preferences persist locally. If the helper crashes before transcription completes, Voco reports the failure without presenting a previous dictation as recovered text.

## Verify changes

Run only the checks relevant to your change:

```sh
npm run typecheck
npm test -- app/main/native-bridge.test.ts app/shared/state.test.ts
./scripts/test.sh
./scripts/check-deferred-dictation.sh
./scripts/check-transcript-polisher.sh
./scripts/evaluate-cleanup.sh
./scripts/check-whisper-cancellation.sh
./scripts/check-focus.sh
./scripts/check-insertion.sh
./scripts/verify-native.sh
npm run verify:compact-ui
npm run verify:menu-bar
```

After installing, verify the current bundle and physical microphone:

```sh
node scripts/verify-installed-version.cjs
./scripts/verify-microphone.sh
npm run verify:insertion
```

`verify:insertion` drives disposable AppKit and Electron editors through the installed desktop and its bundled helper. It checks complete insertion, selection replacement, Unicode, rich-text placeholders, application input events, clipboard restoration, and refusal to report a truncated paste as successful.

To include local recognition in those editor checks:

```sh
VOCO_VERIFY_AUDIO_FIXTURE=/absolute/path/to/speech.wav \
VOCO_VERIFY_EXPECTED_TRANSCRIPT='The literal expected sentence.' \
npm run verify:insertion
```

For the packaged frontend and helper check:

```sh
VOCO_VERIFY_MODEL_DIRECTORY="$HOME/Library/Application Support/Voco/models/moonshine-medium-streaming-en" \
node scripts/verify-desktop.mjs "$HOME/Applications/Voco.app/Contents/MacOS/Voco" --permission-return
```

Direct native inference uses a cached model without microphone or keyboard permissions:

```sh
native/build/VocoNative.app/Contents/MacOS/VocoNative \
  --model moonshine --model-directory /absolute/path/to/model-directory \
  --transcribe-file /absolute/path/to/speech.wav
```

Use `--model parakeet` or `--model whisper` with the corresponding directory. `--download-model` explicitly downloads and verifies that model. `--stream-transcribe-file` checks recognizer updates from a fixture. These checks do not prove a physical Fn key press. See [the verification record](docs/verification.md) and [architecture](docs/architecture.md).

## Local signing

Both app bundles use `VOCO_CODESIGN_IDENTITY`, or the identity stored in `~/Library/Application Support/Voco/signing-identity`. Without either, local builds use ad-hoc signing. A persistent certificate keeps the signing requirement stable across updates so existing macOS grants can survive binary changes.

`scripts/setup-local-signing.sh` creates the local code-signing certificate when needed. Keychain may require authentication or approval for `codesign`. `scripts/verify-signing-identity.sh` checks that different binaries retain the same signing requirement. The installer does not reset permissions. Changing from ad-hoc signing to a certificate requires approving the new identity once. Public distribution requires Developer ID signing and notarization; the current local development certificate is for this Mac.

Moonshine and Whisper model weights use MIT, Parakeet weights use CC BY 4.0, FluidAudio uses Apache 2.0, and whisper.cpp uses MIT. Bundled notices live in `Resources/licenses`.
