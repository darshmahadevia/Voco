# Voco verification

## Rapid insertion, October 9, 2026

The installed desktop now favors a fast first response and rapid text bursts. Words with following context become eligible after 180 milliseconds, down from 550 milliseconds. Recognition polling runs every 120 milliseconds, with the engine's normal analysis cache intact. Delivery uses four, eight, or sixteen whole graphemes and an eight-millisecond minimum interval. Browser acknowledgement governs the actual interval when it takes longer. Capture and finalization use the same delivery path, and finalization adds no extra pacing delay.

The real Electron fixture measures the interval between its first and last input events, excluding app launch and recognition before the first input. Before this change, the three unselected fields took 3126 to 3154 milliseconds and 95 events. Preserved selections took 9334 to 9383 milliseconds. The updated unselected fields take 678 to 683 milliseconds, and the selected input and contenteditable take 2054 to 2066 milliseconds. Each uses 22 events and begins with 16 characters instead of four. Delivery is about 4.6 times faster in these cases. The selected speech textarea takes 5437 milliseconds across 44 events, including recognition during replay. Repeat the measurement with `VOCO_VERIFY_DESKTOP_APP="$HOME/Applications/Voco.app" node scripts/verify-electron-insertion.mjs`.

A stable standalone word can appear before release after 360 milliseconds. Final punctuation appends without replacing that word. The speech fixture exposed premature commitment of the last word in a longer phrase, preserving `record` before the recognizer produced `recognition`. That trailing word now waits for following context or phrase completion. Early words still use the shorter delay, and queued text remains fixed through later corrections.

All 24 Swift tests, seven TypeScript tests, type checking, the insertion lifecycle fixture, native process protocol, and the signed production build pass. Both real AppKit speech cases, all six WebKit cases, and all eight Electron cases pass with the literal expected speech, append-only input events, selection preservation, clipboard preservation, Unicode, empty rich-text placeholders, and literal newlines. One earlier WebKit replay stopped at the existing field-change guard. A standalone replay of all six cases passed without changing that guard. The speed assertion requires a visible first burst and fewer than 40 events for the synthetic fixture, while wall-clock timing is reported without a brittle time limit. The packaged startup and permission-return checks pass with the cached model ready. The installed app and bundled helper are running after reopening through LaunchServices.

## Smooth append-only insertion, October 9, 2026

The installed desktop now buffers provisional words for 550 milliseconds, retains the newest word for context, and inserts stable text in one to four whole-character batches. Completed phrases bypass the wait. Queued text remains fixed through later recognition corrections and finalization. Recognition polling and insertion run independently, and the insertion task exits when no text is waiting. Release waits for the posted batch to settle before draining the final queue. The retained transcript keeps the recognizer's latest wording, which can differ from an earlier committed recognition error.

`scripts/test.sh` passes 20 portable Swift tests. The new cases cover early and late corrections, stability during growing hypotheses, insertions and deletions before the commit boundary, empty and shorter hypotheses, completed phrases, final flush, Unicode, and queue-dependent batching. The direct insertion fixture exercises append-only native and web writes, initial selections, clipboard preservation, changed-caret refusal, and cancellation after one posted character. Focus fixtures, seven TypeScript tests, type checking, native ledger and JSONL protocol checks, and the signed production build pass.

All 16 real AppKit, WebKit, and Electron editor cases pass through the installed desktop identity. The speech fixture produces the literal expected final sentence in both AppKit cases and the selected textarea in each browser engine. WebKit and Electron check every input event for increasing text without rewriting earlier words. The comparison accounts for the rich editor's automatic conversion of spaces to nonbreaking spaces. Empty rich-text placeholders and literal textarea newlines remain supported. The clipboard remains unchanged throughout live insertion.

Repeat the matrix with `VOCO_VERIFY_DESKTOP_APP="$HOME/Applications/Voco.app" ./scripts/verify-live-editors.sh`, adding the speech fixture variables documented below. The standalone helper lacks an Accessibility grant on this Mac. These checks use disposable editors and recorded speech, and do not prove physical Fn delivery or a microphone-to-editor session. Installed bundle contents match the current build and strict deep signature verification passes. The packaged runtime check passes with the cached model ready, preload and helper communication, two windows, and permission-return behavior. The normal app is reopened through LaunchServices after verification.

## UI refinement, October 9, 2026

The refined interface is installed in `~/Applications/Voco.app`. Home retains the centered waveform and two equal headline lines. Settings groups its controls into Speech model, Access, and Dictation. Supporting text and copy controls are larger. Setup uses a compact introduction above a full-width workspace at the native minimum. Practice explains missing requirements and links to the relevant setup step.

Live browser checks at 820 by 640px measured the Settings footer at 618px, the welcome action at 519 to 558px, the model download action at 453 to 492px, and both permission actions inside the first viewport. Expanded help remains reachable by scrolling. Browser preview recovery reserves space for its notice. The normal installed desktop shows the updated Home and Settings, the model ready, microphone and keyboard access Allowed, and Ready to dictate.

Type checking, the production build, and `npm run verify:renderer` pass. Targeted additions verify recovery status, full Home recovery scrolling, a direct practice setup action, and recovery copy failure/retry at the actual 400 by 220px pill size. Copy includes all recovery words. Existing checks still cover responsive centering, fonts, transcript privacy, copy feedback, focus and scroll preservation, startup races, waveform activity, silence, and reduced motion.

The updated packaged Electron runtime passes its preload, two-window, transparent pill, bundled helper, cached Moonshine model, and permission-return checks. Its direct terminal invocation reports microphone required; the normal LaunchServices app reports Allowed. Source reviews found no remaining actionable regressions. Native capture and insertion code did not change in this UI pass. Physical Fn delivery remains the limitation recorded below.

The manual design detector reports font and design-token advisories. Instrument Serif is an intentional setup font. Canonical design documents describe the new layout; generated `.impeccable/design.json` remains stale and can be refreshed separately from `DESIGN.md`.

## Project simplification, October 9, 2026

Three independent source reviews agreed that the unused SwiftUI app and Apple speech pipeline duplicated the current helper without verifying it. Those sources, their exclusive transcript/pause/continuous-shortcut types, and their old permission/recovery fixtures were removed. The shared shortcut and insertion implementations and their direct focus/insertion fixtures now live under `native`. Fn/Globe is the only shortcut implementation; the unused modifier allowance and buffered commit's unreachable live-writer branch were removed. Final buffered insertion now runs in the finalization task without a separate commit task or in-flight flag.

The retained suite has 11 portable Swift tests and seven TypeScript tests. Focus and insertion fixtures, the native ledger and process protocol, audio callback isolation, production renderer regressions, and the Electron runtime's permission-return routing check pass. The full app builds and its signed package passes the runtime check with the cached model. The focus assertion now waits for macOS activation. Editor fixtures use separate logs per case so an earlier success cannot hide a later helper failure. Counts and predecessor checks below describe earlier revisions.

The rebuilt package passed both real AppKit insertion cases. The WebKit and Electron matrices stopped with focus/selection validation errors. Both browser checks also failed against the previously installed build. This pass does not establish a clean browser-editor matrix.

The documented fallback now matches the current helper: buffered text is inserted on release. The pill shows status during capture and transcript text during recovery. The process and synthetic desktop checks do not prove native permission transitions, physical Fn delivery, or a full microphone-to-editor session.

## Earlier installed verification, October 9, 2026

The installed `~/Applications/Voco.app` and bundled helper are both version 0.2.1 and use the persistent Voco Local Development certificate. Production builds, strict deep signature validation, installed-content comparison, repeated installation, and the generated `Voco-0.2.1-arm64.dmg` checksum pass. Node 22.20.0, Swift 6.4, the Xcode Command Line Tools, and macOS 27.0.1 on Apple Silicon are available. Public Developer ID signing and notarization remain unconfigured.

Actual microphone capture passed under the installed desktop identity. A five-second run delivered 52 audio callbacks, 31 speech notifications, and 10 provisional recognition updates. The repeatable `scripts/verify-microphone.sh` also passed with 50 audio callbacks. This check uses the production microphone converter and Moonshine engine, performs no insertion, and removes its temporary transcript report on exit. Capture during silence can pass without a transcript.

All 16 real AppKit, WebKit, and Electron insertion cases passed with `VOCO_VERIFY_DESKTOP_APP="$HOME/Applications/Voco.app" ./scripts/verify-live-editors.sh`. With the speech fixture environment variables from the section below, the matrix also verified actual Moonshine streaming revisions and the literal final sentence. Selection preservation, Unicode revisions, deletion, rich-text placeholders, clipboard preservation, application input events, and changed-caret refusal passed. The standalone helper was denied Accessibility access; running checks through the packaged desktop uses the already approved desktop identity without granting more permissions.

Model checks used actual native processes. Missing models reported missing, damaged models reported a repairable error, and two real downloads received bytes before cancellation. Cancellation and immediate retry removed staging and never installed an incomplete model. The cached architecture-5 English Medium Streaming model passed integrity checks and loaded. Its audio fixture produced seven partial updates and the exact expected final sentence.

The packaged Electron runtime passed the window, preload, helper, model, transparent pill, and permission-return checks. Direct terminal launches reported microphone required while LaunchServices launches had the approved microphone identity. Type checking, seven targeted TypeScript process/protocol tests, the existing Swift core checks, insertion/focus checks, audio callback check, and production renderer regression check passed.

Fixed in this pass: invalid helper output now terminates the failed service and cannot replace recovery with later state; broken pipes cannot crash Electron; recovery keeps current listening text; helper versions follow package metadata; changing build caches cannot silently package an old helper; onboarding practice is an allowed insertion target; obsolete SwiftUI app-entry verification scripts are removed. Local development signatures skip network timestamp requests.

macOS Keyboard settings now show **Press Globe key to: Do Nothing**. Apple Dictation uses the separate microphone key. The installed helper reports Accessibility and shortcut monitoring available, and the normal desktop shows **Ready to dictate** after the update. Physical Fn / Globe press and release remain unverified: the computer automation API rejects `fn` with `keyNotFound`, so this session cannot prove physical key delivery. No system privacy grants were changed.

## Earlier migration record

The migration is verified on an Apple Silicon Mac running macOS 27.0.1 with Node 22.20 and Swift 6.4. The bundled native Moonshine runtime requires macOS 26 or newer.

## Verified behavior

- TypeScript type checking and six process-contract tests pass. The tests exercise real child-process JSON communication, command replies, exit failure, microphone levels, and invalid model/preferences boundaries.
- The production Electron renderer builds with React and Motion. Its preload exposes only the typed Voco API; the actual Electron runtime check loads both windows, communicates with the native helper, and confirms the pill background is transparent.
- The packaged ad-hoc-signed app passed the same Electron runtime check with its bundled helper and a cached model, reporting `model: ready`. Offline native CLI readiness took about 1.9 seconds on this Mac.
- The packaged native helper returned exactly: “The quick brown fox jumps over the lazy dog. This is a local speech recognition test.” from the AIFF fixture.
- A real download test observed byte progress, canceled, immediately retried, then canceled again in an isolated model directory. It returned to missing state and left no installed partial model.
- The official English Medium Streaming architecture-5 model downloaded successfully. Every downloaded file passed size and CRC32C validation, and the native runtime loaded the resulting model.
- All 17 portable Swift core tests and the existing focus, insertion, permission, recovery, and installer checks pass. The focus fixture now supplies its text-area role to reflect the stricter target validation. The insertion checks cover Unicode, clipboard ownership, rejected live writes, safe buffered fallback, caret changes, non-text-control rejection, and nonduplicating completion.

The predecessor checks described in this historical record have since been removed. Current focus and insertion fixtures compile the helper's code from `native/Sources`; `verify-native.sh` and `verify-desktop.mjs --permission-return` exercise the current process and desktop behavior.

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

## Three local speech models

The October 9, 2026 build offers Moonshine Medium Streaming English, Parakeet TDT 0.6B v2, and Whisper Large v3 Turbo. Parakeet is marked Recommended based on the [completed local comparison](../benchmarks/README.md). Setup cannot finish through Continue, practice, or Explore until a model is loaded. Settings supports downloading additional models and selecting an installed model.

The [integration verification record](../benchmarks/results/model-integration-verification.txt) includes nine TypeScript tests, 24 Swift tests, renderer checks, native JSONL protocol checks, and the signed packaged desktop runtime check. The real native IPC test verifies byte-receiving download cancellation and staging cleanup, concurrent-download refusal, incomplete-model rejection, failed activation restoring the previous model, and selection persistence after an independent restart for each of the three families. Installed-model startup must first publish loading or ready; an empty cache first publishes missing.

The renderer check exercises three model choices, per-model download and selection commands, cancellation, disabled switching during dictation, the recommendation badge, and blocked setup completion without a ready model. A browser inspection at 820 pixels confirmed three rows, the Parakeet badge, disabled Explore, and no horizontal overflow.

The baseline benchmark completed 88 measurements and 44 native invocations without failures. A separate [12-measurement Whisper check](../benchmarks/results/2026-10-09-whisper-zero-fix.md) confirmed that the final exact-zero guard suppresses digital-silence text while preserving normal and attenuated speech. Its timings are incidental because other integration checks overlapped.

`npm run pack` passed, strict deep signature verification passed, bundle contents matched the build, and `scripts/install.sh --built` installed the updated app under `~/Applications/Voco.app`. Existing model and preference data were preserved. Verified Parakeet and Whisper weights are installed locally alongside Moonshine. The normal app was reopened through LaunchServices.

These checks use recorded audio and controlled editor-facing state. They do not prove a physical Fn and microphone-to-editor session with the new models. The comparison uses a small English sample; multilingual quality and background-noise suppression remain outside its scope.


## Deferred insertion, October 9, 2026

Normal dictation now records while Fn / Globe is held, finalizes the selected model after release, and inserts the whole transcript once at the current cursor or selection in the original field. No provisional recognition polling or character insertion runs during capture. The listening waveform and finishing spinner remain visible in their respective states.

`./scripts/check-deferred-dictation.sh` compiles the production coordinator and insertion boundary with isolated engine, microphone, shortcut, and editor fixtures. All three model IDs pass capture without writes or polling, delayed finalization after release, duplicate-release prevention, one paste, cursor movement, clipboard restoration, cancellation and stale-result rejection, incomplete-result recovery, recognition errors, changed-field recovery with retention disabled, silence, and short taps. These checks also cancel an insertion waiting for Fn to clear before a paste is posted.

The local Moonshine, Parakeet, and Whisper models each transcribed `/tmp/voco-moonshine-fixture.aiff` through their final-only CLI path. Moonshine and Parakeet returned "The quick brown fox jumps over the lazy dog. This is a local speech recognition test." Whisper returned the same words with a lowercase first letter. This checks actual inference without provisional polling, using recorded fixture audio.

TypeScript checks, nine Vitest tests, 24 Swift core tests, focus and insertion fixtures, native JSONL protocol, audio callback isolation, and the Electron renderer regression check pass. The renderer check covers recording waveform, finishing spinner, release-to-paste guidance, reduced motion, responsive layout, and recovery. The finishing pill also fits a 400-pixel-wide collaborative browser preview. Physical microphone capture and Fn key delivery remain a manual check on the installed app.

The signed bundle was installed at `~/Applications/Voco.app`, and `node scripts/verify-installed-version.cjs` confirms that its contents match the current build. Both the development and installed Electron runtimes passed model loading, helper/preload integration, and permission-return checks. Their isolated verification profiles reported microphone permission required, Accessibility granted, and the shortcut available.


## Amplified pill waveform, October 9, 2026

The listening pill now uses eleven 32px rounded bars, a smooth 1260ms phased wave, stronger microphone gain, and an artificial motion floor while capture is active. Home keeps its existing waveform behavior. Release replaces the waveform with the transcription spinner; reduced motion disables the wave loop.

Type checking, all nine Vitest tests, the production renderer build, and `npm run verify:renderer` pass. The Electron regression samples quiet and zero-level capture over complete wave cycles. It verifies quiet peaks above 24px, an amplitude range above 12px, zero-level peaks above 18px with an amplitude range above 9px, smooth successive samples, a 46px capsule at a 400px by 220px viewport, stopping outside capture, and reduced motion. These use synthetic microphone levels. A collaborative browser inspection confirms the fuller waveform at a 400px viewport.

The signed waveform update is installed at `~/Applications/Voco.app`; the installed-version check confirms the bundle matches the current renderer build.
