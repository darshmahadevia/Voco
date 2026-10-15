# Develop Voco

Voco uses Electron, React, and TypeScript for the interface. A Swift helper handles microphone capture, shortcuts, speech recognition, and text insertion. See the [architecture](architecture.md) for the process boundaries and dictation flow.

Run the commands below from the repository root.

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

`npm run build` builds the Swift helper and production interface using the committed icons. `npm run pack` creates the signed app bundle at `release/mac-arm64/Voco.app`, and `npm run dist` creates a disk image. After changing `Resources/Brand/voco-mark.svg`, run `npm run build:icons` and commit the regenerated assets with the source. Ordinary builds do not rewrite brand assets.

Native dependencies are pinned to Moonshine 0.1.5, FluidAudio 0.9.1, and whisper.cpp 1.9.5. The build verifies the Moonshine archive checksum and Whisper source revision. It does not download speech models. Native artifacts live in `~/Library/Caches/Voco/Native`, with `native/build` linking there. Set `VOCO_NATIVE_BUILD_DIR` to choose another cache. Desktop artifacts live in `~/Library/Caches/Voco/Electron`, with `release` linking there. Installation keeps one app at `~/Applications/Voco.app` and moves the previous bundle to Trash.

## Update the local app when pushing

Enable automatic local updates once per checkout on your Mac:

```sh
npm run setup:push-update
```

Push the checked-out branch to GitHub as usual. The local `pre-push` hook builds, verifies, installs, and opens Voco before Git sends the commits. Builds take place on your Mac. A build failure stops the push before installation. Installation restarts Voco, which clears in-memory recent transcripts. Saved preferences and downloaded models remain available.

Commit or stash changes before pushing so the app matches the pushed commit. Pushes of other branches, tags, and deletions do not update the app. A push with no ref updates does not rebuild. If GitHub rejects the push after the hook completes, the local app has already been updated. Changes pushed from another computer or made on GitHub do not update this Mac.

To push once without updating the app:

```sh
VOCO_SKIP_LOCAL_UPDATE=1 git push
```

To disable automatic updates:

```sh
git config --local --unset core.hooksPath
```

Setup preserves existing hook configurations and reports a conflict rather than replacing them. After cloning another checkout, enable the hook there separately.

## Verify changes

Run only the checks relevant to your change:

```sh
npm run typecheck
node --test scripts/push-update.test.mjs
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
npm run verify:motion
npm run verify:menu-bar
```

`verify:motion` runs `scripts/verify-motion.cjs` against the built renderer in Electron. It checks page transitions, rapid navigation, reduced motion, search focus, Settings anchors, persistent status, retention, and recovery. It writes screenshots and a report to `/tmp/voco-motion`. Build the renderer before running this check.

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

Use `--model parakeet` or `--model whisper` with the corresponding directory. `--download-model` explicitly downloads and verifies that model. `--stream-transcribe-file` checks recognizer updates from a fixture. These checks do not prove a physical Fn key press. See [the verification record](verification.md) and [architecture](architecture.md).

## Local signing

Both app bundles use `VOCO_CODESIGN_IDENTITY`, or the identity stored in `~/Library/Application Support/Voco/signing-identity`. Without either, local builds use ad-hoc signing. A persistent certificate keeps the signing requirement stable across updates so existing macOS grants can survive binary changes.

`scripts/setup-local-signing.sh` creates the local code-signing certificate when needed. Keychain may require authentication or approval for `codesign`. `scripts/verify-signing-identity.sh` checks that different binaries retain the same signing requirement. The installer does not reset permissions. Changing from ad-hoc signing to a certificate requires approving the new identity once. Public distribution requires Developer ID signing and notarization; the current local development certificate is for this Mac.

Moonshine and Whisper model weights use MIT, Parakeet weights use CC BY 4.0, FluidAudio uses Apache 2.0, and whisper.cpp uses MIT. Bundled notices live in `Resources/licenses`.
