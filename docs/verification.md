# Electron migration verification

The migration is verified on an Apple Silicon Mac running macOS 27.0.1 with Node 22.20 and Swift 6.4. The bundled native Moonshine runtime requires macOS 26 or newer.

## Verified behavior

- TypeScript type checking and six process-contract tests pass. The tests exercise real child-process JSON communication, command replies, exit failure, microphone levels, and invalid model/preferences boundaries.
- The production Electron renderer builds with React and Motion. Its preload exposes only the typed Voco API; the actual Electron runtime check loads both windows, communicates with the native helper, and confirms the pill background is transparent.
- The packaged ad-hoc-signed app passed the same Electron runtime check with its bundled helper and a cached model, reporting `model: ready`. Offline native CLI readiness took about 1.9 seconds on this Mac.
- The packaged native helper returned exactly: “The quick brown fox jumps over the lazy dog. This is a local speech recognition test.” from the AIFF fixture.
- A real download test observed byte progress, canceled, immediately retried, then canceled again in an isolated model directory. It returned to missing state and left no installed partial model.
- The official English Medium Streaming architecture-5 model downloaded successfully. Every downloaded file passed size and CRC32C validation, and the native runtime loaded the resulting model.
- All 17 portable Swift core tests and the existing focus, insertion, permission, recovery, and installer checks pass. The focus fixture now supplies its text-area role to reflect the stricter target validation. The insertion checks cover Unicode, clipboard ownership, rejected live writes, safe buffered fallback, caret changes, non-text-control rejection, and nonduplicating completion.

The original SwiftUI coordinator remains only in regression fixtures. Its lifecycle checks protect predecessor behavior but do not by themselves verify the new native coordinator. New native integration checks and fixture transcription provide the migration-specific evidence.

## Repeat the checks

Run the commands in [README](../README.md#verify-changes). `scripts/verify-desktop.mjs` launches actual Electron with an isolated temporary profile, exercises preload/helper communication, captures settings, and exits. `scripts/verify-native.sh` checks the native catalog, mode policy, transcript ledger, and actual process protocol. The native checks cover provisional revisions, completed-line identity, phrase spacing, empty finals, and stale sessions. They do not drive physical microphone or key events. Pass an explicit cached model directory and audio fixture to the native CLI for real recognition.

The independent correctness review identified hold-to-continuous transcript loss, recovery dismissal, and recovery actions after a helper exit. The implementation now promotes the same session in place, permits explicit dismissal, and handles copying/dismissal in Electron when the helper is unavailable. Setup offers Restart Voco for a service failure.

Build artifacts live in `~/Library/Caches/Voco/Electron`; `release` links there. Packaging clears macOS extended metadata before and after signing to avoid Finder metadata breaking the build.

## Manual checks

Grant microphone and keyboard access to the packaged **Voco** app, then check physical Fn hold/release, real microphone audio, and insertion into the apps you use. Automated audio fixtures do not prove physical key delivery, microphone permission, or compatibility with every editor.

Local app bundles use the configured signing identity, with ad-hoc signing as the fallback. Developer ID signing and notarization are required before public distribution.

Historical SwiftUI verification is retained in [the pre-migration record](migration/pre-electron-verification.md); its installed-app results do not describe the Electron bundle.

The signed helper inherits the Audio Input entitlement required by the hardened runtime ([Apple documentation](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.device.audio-input)). This packaging check complements, rather than replaces, a permission-granted microphone test.

For a packaged permission check, launch the app through Finder or `open`. A helper launched directly from a terminal can inherit the terminal app’s permission identity. The desktop verification report includes the permissions observed by the running helper. If an enabled Accessibility entry belongs to an earlier ad hoc signed build, remove that entry and add the current Voco.app again. macOS can retain the old code requirement even while its switch remains enabled.

`node scripts/verify-desktop.mjs --permission-return` checks that a requested permission brings setup forward once, closing setup cancels that return, ordinary updates leave it closed, and a native-service failure reveals setup. It uses real Electron windows and IPC with synthetic permission snapshots. It does not automate macOS consent dialogs.

`./scripts/check-audio-callback.sh` invokes the production audio tap block on a background queue with an AVAudioConverter. It checks conversion and delivery of speech notifications to the main actor. It does not record the physical microphone.

## Live dictation updates

The live revision checks cover preserving an initial selection, inserting after its end, revising only session text, shortening and deleting hypotheses, Unicode offsets, pause continuation, changed-document and changed-caret rejection, safe first-write fallback, and cancellation between keyboard input batches. The 18 Swift core tests, insertion/focus fixtures, five TypeScript tests, native protocol/ledger checks, audio callback check, and actual Electron window/preload/helper check pass. The listening pill displays the partial transcript at a 400-pixel viewport without horizontal overflow.

The real native Moonshine engine produced seven distinct provisional updates from `/tmp/voco-moonshine-fixture.aiff`, including "The quickness" before correcting it to "The quick brown fox jumps over the lazy dog. This is a local speech recognition test." The final transcript matched that expected sentence. This verifies streaming recognition from an audio fixture, not the physical microphone.

All 14 real editor cases passed after enabling the helper: two native AppKit NSTextView cases, six WebKit browser cases, and six Electron cases. The browser and Electron cases cover input, textarea, and contenteditable, with and without initial selections. Each receives live input events and keeps its application state equal to the visible value. The audio fixture also passed with real Moonshine provisional revisions in both native cases and the selected textarea case in each web engine, with the literal expected final sentence checked. Clipboard formats, data, and change count remained unchanged during live updates.

The real Electron tests exposed asynchronous selection propagation: AX can acknowledge a range change before the browser renderer and accessibility tree settle. Live keyboard writes now require the requested range to remain correct across two reads before typing or restoring a preserved selection. The caret-movement test waits for its own simulated user action too. The same real editor matrix passed again after this correction.

Real editor insertion checks initially stopped because macOS denied Accessibility access to the rebuilt helper. On this macOS version the permission page is **Privacy & Security > Device Control and Data Access**. Enable `native/build/VocoNative.app` there after building. Ad hoc signatures change on rebuild. If toggling the existing entry does not refresh the grant, remove and re-add this same helper. Build artifacts now live in `~/Library/Caches/Voco/Native`, with `native/build` linking there, to avoid synced-folder metadata breaking signatures.

The full repeatable matrix builds only editor fixtures and keeps the helper signature intact:

```sh
./scripts/verify-live-editors.sh
```

To repeat the speech checks, set `VOCO_VERIFY_AUDIO_FIXTURE`, `VOCO_VERIFY_MODEL_DIRECTORY`, and `VOCO_VERIFY_EXPECTED_TRANSCRIPT` before running that command. The recorded expected transcript is `The quick brown fox jumps over the lazy dog. This is a local speech recognition test.`

Run the focused check below without rebuilding the helper between the permission grant and verification.

For a disposable native or browser editor, focus a field containing exactly `Before selected after`. Place the caret in the middle or select `selected`, then run:

```sh
./scripts/verify-live-insertion.sh 'Before selected after'
```

The command verifies actual editor text and selection after each correction, clipboard data and change count, long Unicode batches, deletion, committed phrase continuation, and refusal after moving the caret. To feed real Moonshine provisional results into the same field, add `--audio-fixture PATH --model-directory PATH`. The check modifies only the explicitly supplied disposable document and leaves the caret at its start after the refusal test.

For a repeatable Electron editor matrix, run:

```sh
node scripts/verify-electron-insertion.mjs
```

This opens a disposable Electron window, tests input, textarea, and contenteditable fields with and without selections through the real native helper, and verifies that the editor's input events update its application state. `native/Tests/editors.html` provides the same fields for browser checks, with an input-event log. Neither command changes system permission settings.

To verify recognition without editor permission:

```sh
native/build/VocoNative.app/Contents/MacOS/VocoNative \
  --stream-transcribe-file /tmp/voco-moonshine-fixture.aiff \
  --model-directory "$HOME/Library/Application Support/Voco/models/moonshine-medium-streaming-en"
```

The final development Electron runtime check loaded the cached model and passed its window/preload/helper contract. Its permission snapshot reported microphone required, Accessibility false, and shortcut false under the development Electron parent. The real editor matrix launches the granted helper through LaunchServices, which passed the native and web insertion checks. These results do not establish physical microphone capture or physical talk-key delivery in the packaged app; those remain the manual checks described above.

Fn / Globe hold-to-talk is now the only desktop dictation mode. The continuous shortcut, pause setting, and alternate talk-key settings have been removed; older shortcut preferences are ignored. Live transcript polling continues until Fn is released.

The single-mode change passed `npm run build`, all five TypeScript tests (including rejection of continuous listening state), native session-ledger and JSONL protocol checks, and both AppKit insertion cases. Renderer previews confirm a fixed Fn / Globe shortcut and release-to-finish guidance, with no continuous Stop button. The rebuilt helper’s existing Accessibility entry was refreshed and the AppKit checks confirmed access. Physical Fn delivery still requires the manual check above.

The installed-app mismatch was reproduced by `node scripts/verify-installed-version.cjs`: the installed `out/main/index.js` differed from the current build. The old bundle also contained Fn + Space instructions and lacked the partial-transcript display. Installing the current signed bundle fixed the check. Only `~/Applications/Voco.app` remains as a standalone desktop app; `build/Voco.app` and `release/mac-arm64/Voco.app` resolve to that installed bundle. Older Voco/Utter bundles and installers were moved to Trash, preserving model and preference data. The install script now checks bundle contents, moves the bundle into Applications, and leaves build links instead of additional copies. Repeating `scripts/install.sh --built` passed without replacing it.

The installed app's live interface shows only Fn / Globe and reports Ready to dictate after refreshing the existing permissions. The listening renderer preview shows partial words and Release Fn / Globe to finish with no continuous-mode controls. The installed Electron runtime verification passed with its real helper and cached model. Its separate verification invocation reported keyboard/shortcut access granted and microphone permission required; the normal LaunchServices app shows microphone access allowed. Physical Fn and microphone testing remains a user check.

T3 Code first-word failure: reproduced in the real T3 composer, where an empty rich paragraph exposes AXValue `"\n"` and then removes that placeholder on first keyboard input. The trace reported expected length 10 and actual length 9 with identical caret 9. The writer now learns that exact empty-placeholder transition while keeping ordinary text/range/focus checks. Empty placeholder normalization is session-local; a literal textarea newline was separately verified to remain intact. The real T3 composer passed five partial revisions, including deletion to empty and a later committed phrase, plus rejection of a changed caret and unchanged clipboard count. No test message was sent; the draft was cleared afterward. All 16 AppKit/WebKit/Electron editor checks and the insertion lifecycle regression fixtures passed. Temporary debug probes were removed.

Both native and desktop builds now accept `VOCO_CODESIGN_IDENTITY`, falling back to the persistent identity name in `~/Library/Application Support/Voco/signing-identity`. This Mac now has the trusted `Voco Local Development` code-signing certificate and private key in the login Keychain. The signing stability check passed: different binaries retained the same designated requirement. The installed desktop bundle and native helper use that certificate, and deep signature validation passed. The installation script does not reset TCC grants.

After installing the certificate-signed build, the existing desktop Accessibility entry was refreshed once for the new identity. The normal installed app now shows the model downloaded, microphone Allowed, keyboard access Allowed, and Ready to dictate. Physical speech and Fn delivery remain the user test.

## Startup and waveform regression

After building, run `npm run verify:renderer`. This check loads the production renderer in Electron with a controlled native API. It verifies that unknown startup state does not show onboarding, model warmup opens Home without setup prompts, and a late initial read cannot overwrite a newer state. Genuine first-run setup stays open until the user finishes it.

The same check verifies independently animated waveform bars during steady input, a three-pixel baseline in silence, the floating pill, and reduced-motion behavior. It uses synthetic microphone levels; it does not verify physical microphone capture. CI runs this check after building the app.
