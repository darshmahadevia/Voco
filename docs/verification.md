# Voco verification

## Current installation, October 10, 2026

The current app is installed at `~/Applications/Voco.app`. Both the Electron bundle and Swift helper use the persistent **Voco Local Development** certificate. Strict deep signature verification passes. The packaged renderer, preload, main process, and helper build UUID match the source build. The helper targets arm64 and macOS 26, and links system frameworks rather than dependency libraries in the build cache.

The environment has macOS 27.0.1 on Apple Silicon, Node 22.20.0, Swift 6.4, Xcode Command Line Tools, and a managed CMake executable at `~/Library/Caches/Voco/BuildTools/cmake/bin/cmake`. `codesign`, `xcrun`, `plutil`, `iconutil`, `hdiutil`, and `ffmpeg` are available. The native build uses pinned Moonshine 0.1.5, FluidAudio 0.9.1, and whisper.cpp 1.9.5 dependencies.

The initial source build failed because required build, packaging, and installation scripts were deleted while package.json still referenced them. The restored build uses Swift Package Manager for the current three-engine helper. Normal development startup also failed with `ELECTRON_RUN_AS_NODE=1`; the dev command now removes that flag and the actual development frontend/helper verification passes.

## Verified behavior

- Production TypeScript and Swift builds pass. Eight targeted TypeScript state and real-child-process bridge checks pass. Seven portable gesture checks and the current focus, insertion, deferred dictation, shortcut monitor, and native JSONL protocol checks pass.
- The production renderer passes 45 layout scenarios and onboarding, search, copy feedback, calendar, and goal interactions. Menu startup, page navigation, close/reopen behavior, preload access, transparent pill, two-window layout, and permission-return behavior pass in real Electron.
- Launching the installed app through LaunchServices reports `model: ready`, microphone granted, Accessibility granted, and the global shortcut monitor active. Direct terminal launches can have a different microphone permission identity; they do not establish the installed app's grant.
- Actual microphone capture through the installed desktop and bundled helper passes. During playback of the local speech fixture through the Mac's built-in speakers, the microphone delivered 51 audio callbacks, 36 speech callbacks, and 11 partial recognition updates. The microphone check deletes its temporary transcript report afterward.
- Twenty repeated Moonshine sessions transcribe the exact local speech fixture through queued audio, finish successfully, and cancel a second stream. Completed and canceled stream IDs are released instead of accumulating for the lifetime of the helper.
- All three installed models load and transcribe the local speech fixture. Model files remain outside the app bundle in Application Support. Missing and damaged model directories report repairable state. Real downloads publish byte progress; cancellation, immediate retry, and staging cleanup pass. HTTP errors now preserve their status rather than reporting cancellation.
- The installed desktop forwards the buffered insertion verification to its bundled helper. Both AppKit cases pass with actual local recognition. Nine Electron cases pass, including input, textarea, contenteditable, selected text, an empty rich-text paragraph, a maxlength-limited input, and an audio-to-textarea case. Exact field values and caret positions are checked. Electron receives one complete input event, and clipboard formats and bytes remain unchanged after restoration.
- Native and clipboard writes that change the field to an incomplete result now report failure without retrying the insertion. The deferred coordinator retains the full transcript for recovery. Helper failure during an unfinished session no longer presents the previous dictation as recovered text.

The raw output for `/tmp/voco-subtract-fixture.wav` differs in punctuation and capitalization by engine. Moonshine returns `The quick brown fox jumps over the lazy dog, this is a local speech recognition test.` Parakeet returns `The quick brown fox jumps over the lazy dog. This is a local speech recognition test.` Whisper Turbo starts that same two-sentence result with lowercase `the`. The editor speech checks assert the literal Moonshine result rather than forcing all engines to format the text identically.

The unused live-insertion writer, stability buffer, types, tests, editor fixtures, and CLI modes were removed. Production records while listening and inserts the completed transcript once after release or continuous-stop. Current editor checks exercise that path. Earlier live-insertion timing and model comparisons in other documents describe earlier builds.

## Repeat targeted checks

```sh
npm run typecheck
npm test -- app/main/native-bridge.test.ts app/shared/state.test.ts
./scripts/test.sh
./scripts/check-deferred-dictation.sh
./scripts/check-focus.sh
./scripts/check-insertion.sh
./scripts/verify-native.sh
npm run verify:compact-ui
npm run verify:menu-bar
```

After building and installing:

```sh
node scripts/verify-installed-version.cjs
codesign --verify --deep --strict "$HOME/Applications/Voco.app"
./scripts/verify-microphone.sh
npm run verify:insertion
```

Include local recognition in the disposable editor checks:

```sh
VOCO_VERIFY_AUDIO_FIXTURE=/absolute/path/to/speech.wav \
VOCO_VERIFY_EXPECTED_TRANSCRIPT='The literal expected recognition output.' \
npm run verify:insertion
```

`VOCO_VERIFY_MODEL_DIRECTORY` selects the cached Moonshine model directory for those checks. It defaults to `~/Library/Application Support/Voco/models/moonshine-medium-streaming-en`. `VOCO_VERIFY_DESKTOP_APP` can select another installed bundle. Editor checks take focus while they run; run them sequentially with other app automation.

`verify-desktop.mjs` tests the actual packaged frontend and helper with an isolated Electron profile. Pass the installed executable, `--permission-return`, and `VOCO_VERIFY_MODEL_DIRECTORY` as shown in README. `verify-microphone.sh` uses LaunchServices to preserve the installed app's microphone identity.

Electron 44 clipboard writes return promises. Recovery copying after helper failure now waits for the write before clearing the recovery session. The editor fixture reads clipboard items asynchronously and compares their bytes without logging their contents. See the [Electron clipboard API](https://www.electronjs.org/docs/latest/api/clipboard).

## Remaining verification boundary

A physical Fn or Globe press cannot be driven by this session's computer-use API. The attempted `pressKey("fn")` returned `keyNotFound("fn")`. Gesture and shortcut-event handling pass automated checks, and the installed helper's event tap starts with the existing Accessibility grant. This does not establish physical key delivery or one uninterrupted physical-key, microphone, transcription, and editor session.

The local app is signed for development on this Mac. Developer ID signing and notarization are unconfigured for public distribution. No privacy grants were reset or broadened during this work.

## Local output quality, 2026-10-14

The output-quality change adds Fast, Balanced, and Accurate without changing the selected speech engine. Verification covered:

- TypeScript type checking and 27 renderer, protocol, usage, and process-bridge tests.
- The compact Electron check passed 45 layouts, including all three output options, disabled preview actions, and the Polishing spinner.
- Native cleanup cases covered fillers, quoted phrases, sentence boundaries, decimal and signed quantities, names, negations, empty output, and raw-text fallback.
- Deferred coordinator fixtures covered frozen preferences, cancellation during suspended cleanup, late results, missing recognition callbacks, cleanup deadlines, and single insertion for all three engine adapters.
- The FoundationModels smoke check reported available and returned `Alice has 12 tickets, not 13.` for `Um, Alice has 12 tickets, not 13.` without a fallback notice.
- The real native JSONL process accepted Balanced, rejected an unknown mode, and published the new state fields.

A synthetic `say` audio fixture spoke `Um, please send Alice twelve tickets, not thirteen.` Moonshine returned `Hum. Please send Alice 12 tickets, not 13. 13.` Parakeet and Whisper returned `Um, please send Alice 12 tickets, not 13.` This single synthetic example proves local inference runs and exposes recognition differences. It is not an accuracy benchmark. Cleanup intentionally does not guess that `Hum` is a filler or delete an arbitrary repeated number.

The native helper built after installing the missing CMake prerequisite. Physical microphone and Fn-key dictation were not exercised for this change. The installed desktop bundle was not replaced by these source checks.

The focused `scripts/check-whisper-cancellation.sh` check also passed against the cached Whisper model. It exercised real decoding, cancellation, reopening, suppression of queued partial and final results, and subsequent transcription in the same context. Cancellation uses whisper.cpp's cooperative abort callback. The final `npm run build` and native JSONL check passed after the reliability fixes.
