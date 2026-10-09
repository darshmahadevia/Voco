# Voco

Local English dictation for macOS. Hold Fn or Globe to write into the active text field. Release to finish.

The interface uses Electron, React, TypeScript, and Motion. A bundled native helper runs Moonshine Medium Streaming and handles macOS microphone capture, shortcuts, and safe text insertion. The app needs no account or transcription API key.

## Run the app

The first release targets Apple Silicon Macs running macOS 26 or newer. Development requires Node.js 22 or newer and the Xcode Command Line Tools. The native build downloads a pinned Moonshine runtime library, but never downloads a speech model.

```sh
npm install
npm run dev
```

To build a local app bundle:

```sh
./scripts/install.sh
open ~/Applications/Voco.app
```

To create the disk image installer, run `npm run dist`. Build artifacts live in `~/Library/Caches/Voco/Electron`; `release` links to that directory to avoid synced-folder metadata affecting signing. The install script keeps one installed app in `~/Applications/Voco.app`; build links point to that copy after installation. Local bundles use the configured development certificate, with ad-hoc signing as the fallback. Public distribution requires a Developer ID signature and notarization.

## Set up dictation

1. Open Voco. First launch opens guided setup. Click **Get started**, then **Download speech model**. You can also open **Set up Voco** from the sidebar. Setup shows progress and supports cancellation or retry. The English Moonshine Medium Streaming model downloads into Voco's Application Support directory, outside the app bundle.
2. Click **Allow** next to Microphone. Grant microphone access to Voco.
3. Click **Allow** next to Keyboard access. Enable Voco in macOS **Privacy & Security**. The page is called **Accessibility** on macOS 26 and **Device Control and Data Access** on macOS 27. If approval for an earlier Voco build is still listed, remove it, then add the current app shown in Finder and enable it. If access is granted but the shortcut is unavailable, use **Restart Voco**.
4. In macOS Keyboard settings, set **Press Globe key to** to **Do Nothing**. Disable any Apple Dictation shortcut that uses the same key.
5. Continue to **Your first words** and try dictation in the practice field. Click **Open Voco** to reach Home. To dictate elsewhere, focus a text field in another app, hold Fn or Globe, and speak.

Once the model is downloaded, recognition runs offline. App updates preserve the model. A missing or damaged model returns setup to a repairable state instead of starting a hidden download.

Fn / Globe is the only dictation shortcut. Escape stops capture and leaves words already written intact.

## Text insertion and recovery

Voco revises only the text it inserted into a supported native field. A changed caret, document, app, or field stops automatic writing. Password fields are rejected.

Voco shows Moonshine's partial words while you speak. Native fields use Accessibility text replacement; readable web and Electron fields with writable selection ranges use keyboard input events so their application state updates too. Live corrections revise only text inserted by the current session and leave the clipboard untouched. Existing selections remain selected, with dictation inserted after them. A document edit, caret movement, or focus change stops further writing.

Fields that reject live correction use buffered insertion after a pause or release. During capture, the pill shows a waveform and status only. It does not show a Buffered badge or partial transcript. Buffered insertion checks the original document and selection and preserves selected text. Paste restores the previous clipboard if another app has not changed it. Voco never presses Return or submits a form.

If insertion fails, the pill offers the retained transcript for copying. **Keep last transcript** holds one transcript in memory until you quit. Turning it off clears that saved transcript. Audio and transcript history are not written to disk.

## Verify changes

```sh
npm run typecheck
npm test
npm run build
./scripts/verify-native.sh
node scripts/verify-desktop.mjs
./scripts/test.sh
./scripts/check-focus.sh
./scripts/check-insertion.sh
./scripts/verify-microphone.sh
```

The packaged desktop can also be verified directly:

```sh
VOCO_VERIFY_MODEL_DIRECTORY="/absolute/path/to/model-directory" \
  node scripts/verify-desktop.mjs release/mac-arm64/Voco.app/Contents/MacOS/Voco
```

Native inference can be checked with a local audio fixture:

```sh
native/build/VocoNative.app/Contents/MacOS/VocoNative \
  --model-directory /absolute/path/to/model-directory \
  --download-model
native/build/VocoNative.app/Contents/MacOS/VocoNative \
  --model-directory /absolute/path/to/model-directory \
  --transcribe-file /absolute/path/to/audio.aiff
```

The first command is an explicit download. The second uses the cached model without microphone or keyboard permission. This does not prove physical microphone capture or shortcut delivery.

`npm run dev:ui` opens a renderer-only preview. Its named example states are labeled **Interface preview**. Native actions are inactive, while Home, Settings, and onboarding navigation remain active. Use the Electron app for model downloads, permissions, and dictation.

The predecessor SwiftUI sources remain as regression fixtures for the existing lifecycle and insertion checks. They are not packaged or launched by the Electron app. See [the migration architecture](docs/migration/architecture.md) and [verification](docs/verification.md).

## Scope

macOS ships first. Windows support follows after macOS dictation is stable. The Electron interface and typed helper contract can be reused with a Windows adapter.

Moonshine code and English streaming models are MIT licensed. See [Moonshine's model catalog](https://moonshine-voice.readthedocs.io/en/stable/models/available-models/).

For real native, WebKit browser, and Electron live insertion checks, install the app and run `VOCO_VERIFY_DESKTOP_APP="$HOME/Applications/Voco.app" ./scripts/verify-live-editors.sh`. This uses the desktop app’s existing keyboard permission. Standalone helper checks need their own grant. The fixtures exercise selections, Unicode revisions, deletion, clipboard preservation, and caret-change refusal. See [the verification record](docs/verification.md#live-dictation-updates) for speech fixture options.

### Keep permissions across local updates

Ad-hoc builds have a different code-signing requirement after native code changes. For permissions to survive updates, sign both the desktop app and helper with the same persistent certificate and keep their bundle identifiers unchanged. Run `scripts/setup-local-signing.sh` once to create a code-signing-only local certificate in your login Keychain, then `scripts/install.sh` to build and install with it. macOS may ask you to authenticate certificate trust and allow `codesign` to use the key. `scripts/verify-signing-identity.sh` checks that changed binaries retain the same signing requirement. For an existing certificate, set `VOCO_CODESIGN_IDENTITY` to an installed signing identity, or store that identity in `~/Library/Application Support/Voco/signing-identity`. Both build steps use it and fail if it cannot sign the app. A Developer ID Application certificate is the distribution option; a persistent local signing certificate can be used for development on this Mac. Changing from ad-hoc signing to certificate signing requires approving permissions once for the new identity. Voco does not reset permissions during installation.

Apple explains the identity requirements in [TN3127](https://developer.apple.com/documentation/technotes/tn3127-inside-code-signing-requirements).
