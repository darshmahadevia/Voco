# Verification record

Historical document for an earlier Voco implementation. Commands and design details below may refer to removed code. See the [current README](../../README.md), [architecture](../architecture.md), and [development guide](../development.md).

Verified on an Apple Silicon Mac running macOS 27.0.1, using the installed Swift 6.4 Command Line Tools and macOS 27 SDK. The app's deployment target is macOS 26.

## October 8 editor insertion compatibility

The user reported that Notes and browser insertion worked but T3 Code and ChatGPT insertion did not. Voco's local logs showed repeated `Text could not be inserted` recovery within roughly 28–31 ms of the first speech result. That places the failure in the first live Accessibility update, before buffered paste. T3 Code exposes its message composer as a settable text area inside an HTML Accessibility tree. These observations support a failed live-write path; they do not establish that every destination fails for the same reason.

The new `./scripts/check-insertion.sh` ran against the original insertion code and failed with `InsertionError.unavailable` when a web editor advertised writable attributes but rejected the live replacement. After the change, it passes exact-text checks through the actual `FocusTarget`, `LiveTextWriter`, and `AppModel` code. Covered behaviors include normal paste in web editors, native live correction, Unicode, rejected and ignored first writes, rejected selection writes, unreadable results after insertion, partial writes, failed later corrections, identical selected-text replacement, clipboard restoration and ownership, failed paste, focus and permission guards, continuing dictation after buffered fallback, final corrections, pause spacing, and a nonduplicating finish.

The first actual T3 Code run inserted one phrase and then rejected the next with `Another shortcut key is held`. The paste key-up event retained the synthetic Command flag, which remained visible in the combined session state. The fixture was extended to model posted modifier flags and reproduced the same `InsertionError.modifiers` failure. Releasing the synthetic chord on key-up fixes the repeated-phrase failure; the updated regression passes while still rejecting genuinely held shortcut modifiers.

All 17 core tests, recovery, focus, permission lifecycle, and installer checks pass. The release build, strict installed signature check, shell syntax check, plist validation, and `git diff --check` pass. CI now includes the insertion check.

The update is installed at `~/Applications/Voco.app`. The installer reset Voco's grants because the old app's designated signing requirement pinned its previous code hash. Initially the post-install shortcut check reported `Accessibility: required` and `Global shortcut: unavailable`. After the user authorized screen control, Voco's switch was enabled in System Settings. Setup showed Allowed and `check-shortcut.sh` passed with `Accessibility: granted`, `Global shortcut: available`, and `Keyboard access: ready`.

The final installed build passed `scripts/verify-focused-insertion.sh` in the actual T3 Code message composer. Three consecutive buffered insertions produced the exact expected text, including Unicode and a second phrase. The resulting draft was independently read through the native Accessibility tree and then cleared without sending it. `scripts/verify-insertion.sh` also passed five exact TextEdit insertions, native live corrections, Unicode, phrase continuation, and rejection of caret movement. The final shortcut check reports granted access, an available shortcut, and ready status. These checks use the installed signed app rather than a separate test executable.

The focused-editor verifier requires an exact disposable draft sentinel and a caret at its end. It never submits the draft. The screen-control tool operates on app windows in the background; reopening T3 Code through Finder establishes the actual foreground app for this check. The user approved the final microphone dialog, and Voco's setup then showed English ready, Keyboard access Allowed, and Ready status. The native ChatGPT app is unavailable to the computer-use tool, so its native composer has not been verified. Automated fixtures do not prove compatibility with every macOS application. Physical microphone holds and continuous listening remain manual checks.

## Reliability pass on October 8, 2026

The repository is private at [darshmahadevia/Voco](https://github.com/darshmahadevia/Voco). The baseline and each verified fix were pushed separately to `main`.

Two defects were reproduced before fixing them:

- Live correction treated canonically equivalent Unicode text as identical even when its UTF-16 representation changed. This caused caret drift and misplaced subsequent edits. Exact UTF-16 snapshot comparisons and scalar comparisons within grapheme boundaries now preserve Accessibility ranges. Selections that split a surrogate pair are rejected. Regression tests also reject a field changing only its Unicode representation.
- A quick talk-key tap after canceling continuous dictation could overwrite the full saved transcript with its last uncommitted phrase. Session text now resets when capture starts. The actual app-model regression changed from `Saved transcript after quick tap: Second phrase.` to `Saved transcript after quick tap: First phrase. Second phrase.`

Current checks:

- `./scripts/test.sh` passes all 17 core tests.
- `./scripts/check-recovery.sh` passes the source-level lifecycle regression. The script appends a same-file test extension to a temporary copy of the app model, compiles the actual supporting sources, and simulates key arming and release without microphone capture. Temporary compiler artifacts are removed, and the transcript-retention preference is restored.
- `./scripts/build.sh` produces the release bundle; strict signature verification passes.
- Shell syntax and `Resources/Info.plist` validation pass.
- Native setup and status previews render; the setup image was inspected.
- File and paced-stream transcription complete with the real speech analyzer. The synthetic fixture says "Hello, this is Voco. Speech recognition runs on my Mac." Recognition returns "Hello, this is Vako. speech recognition runs on my Mac." The proper name differs; this is a speech-quality limitation, not exact recognition of every word.
- The repeated-phrase fixture passes `--verify-pauses`, with two complete batches and no repeated text on stopping.
- GitHub Actions runs core tests, the recovery check, and the signed release build on macOS 26. The [run containing both fixes](https://github.com/darshmahadevia/Voco/actions/runs/37836485471) passed every step.

The new build's LaunchServices diagnostic reports `Accessibility: required` and `Global shortcut: unavailable`. New-build TextEdit insertion, physical Fn/Fn+Space capture, microphone use, browser fields, and multiple displays remain unverified. The previously installed Utter build was left in place. Source review also confirms that destinations without a readable Accessibility value cannot provide proof of successful insertion; the fallback deliberately avoids a second insertion after an acknowledged write.

Earlier entries below describe previous builds and do not establish live behavior on this build.

## T3 Code cursor follow-up

The user reported a visible cursor that Voco sometimes could not detect in T3 Code. The original target capture made a single focused-element query without requesting Electron's Accessibility tree. Missing focus was retained as a nil element until startup, then reported as a changed field.

`FocusTarget` now requests `AXManualAccessibility` once during capture, as described in [Electron's accessibility guide](https://github.com/electron/electron/blob/main/docs/tutorial/accessibility.md). A missing field gets a bounded retry on the captured process before microphone startup. After a field resolves, validation continues to require the same app and exact field identity. App switching, changed fields, secure fields, and canceled startup still stop writing. An exhausted lookup now reports that the focused field could not be read.

`./scripts/check-focus.sh` compiles the actual target implementation with simulated Accessibility and workspace boundaries. `./scripts/check-focus.sh 34ee4ed` runs the minimal inactive-tree fixture against the original implementation and prints `Electron cursor with initially inactive accessibility: MISSING`. The current check prints `FOUND`. It also verifies delayed publication, one accessibility request per capture, read-only validation, the retry bound, app and field switching, secure fields, native apps that reject the Electron attribute, missing permissions, invalid responses, and cancellation. An unreadable field is reported as unavailable rather than incorrectly claiming the field changed.

This verifies the documented Electron compatibility path and its safety checks. The corrected app is installed at `~/Applications/Voco.app`, and its strict signature check passes. Its shortcut diagnostic reports `Accessibility: required` and `Global shortcut: unavailable`. Live detection and insertion in the user's T3 Code editor remain unverified until Keyboard access is enabled for this development signature. The older Utter process was left running; quit it before using the new app so both do not handle the same shortcut.

## Completed checks

- `./scripts/build.sh` produced the release app with no external dependencies.
- `codesign --verify --deep --strict build/Voco.app` passed for the local ad-hoc signature.
- `./scripts/test.sh` passed six Swift Testing checks covering modifier holds, repeated events, shortcut cancellation, provisional revisions, overlapping results, and time ordering.
- `plutil -lint Resources/Info.plist` passed.
- `bash -n scripts/build.sh scripts/test.sh scripts/install.sh` passed.
- `--render-previews` rendered the actual SwiftUI setup, listening, and recovery views. The images were inspected. They contain illustrative text and do not prove live dictation.
- The app launched through `open build/Voco.app`, and its process was confirmed running.

## Speech engine check

The system `say` command generated a local fixture:

```sh
say -o /tmp/voco-fixture.aiff 'Hello, this is Voco. Speech recognition runs on my Mac.'
build/Voco.app/Contents/MacOS/Voco --transcribe-file /tmp/voco-fixture.aiff
```

The engine returned:

```text
Hello, this is Voco, speech recognition runs on my Mac.
```

All spoken words matched the fixture. Sentence punctuation differed. Two measured file runs took about 0.41 and 0.56 seconds, including preparation. These numbers are smoke-test observations, not live dictation latency benchmarks.

## Live checks still required

macOS permissions must be granted by the user. These behaviors have not yet been verified end to end:

- Physical Fn or Globe hold and release on the user's keyboard.
- Microphone capture, partial results, and finalization during a live hold.
- Insertion and caret behavior in TextEdit and browser text fields.
- Escape cancellation, keyboard-combination cancellation, and a changed text field during live dictation.
- Positioning on multiple displays and over a full-screen app.

Use a disposable TextEdit document for the first live test. Confirm that the app inserts once and does not steal focus. Move to another text field during capture and confirm that Voco offers Copy instead of inserting.

## Toolchain notes

The installed Command Line Tools include Swift Testing, but their build driver did not automatically load the macro plugin. `scripts/test.sh` supplies the installed plugin when that toolchain layout is present and disables XCTest, which this installation does not include.

This workspace is in a synced Documents folder. The file provider adds Finder metadata to copied app bundles and breaks strict signature verification. The build script assembles and signs the app in the local cache, then creates a workspace link to that bundle.

## Setup correction after the first live attempt

The user reported that Voco was missing from Input Monitoring and could not be added. The initial implementation used a passive CGEvent tap and gated setup on that separate permission. That path has been removed.

The current shortcut monitor uses AppKit's global and local event monitors under Accessibility access, which the app also needs for text insertion. Setup has one Keyboard access row and a Finder reveal action for manual selection of the app. The install script copies the signed bundle to `~/Applications/Voco.app`, outside the build cache and synced workspace.

The physical key and live transcription checks remain pending until the corrected Keyboard access grant is enabled. No automated test can grant macOS privacy permissions on the user's behalf. `--check-shortcut` provides a command that checks actual trust and monitor installation without claiming to test physical key delivery.

The corrected release was installed and opened from `~/Applications/Voco.app`. Its signature verification and shell syntax checks passed, and the six core tests passed again. The updated native setup render was inspected and passed an independent visual review. A file transcription check returned the same spoken words in about 0.31 seconds.

Before the corrected privacy grant, the installed app's shortcut diagnostic exited with status 2 and printed:

```text
Accessibility: required
Global shortcut: unavailable
```

The user subsequently enabled Keyboard access. The LaunchServices diagnostic printed `Accessibility: granted` and `Global shortcut: available`. The user confirmed physical Fn capture and live microphone transcription. Insertion succeeded once but then failed intermittently without a recovery message.

## Follow-up for disappearing text and missing menu

The app now populates its menu at launch instead of leaving it empty until a menu delegate callback. Settings can also be reopened by opening the running app. Transcript retention is enabled by default, can be disabled in settings, and keeps one transcript in memory. Empty final results preserve a nonempty preview in recovery instead of dismissing it. Cancellation also preserves the last preview for manual copying when retention is enabled.

The insertion fallback uses a normal paste, restores prior clipboard representations unless they changed externally, and checks for an actual text change when the focused element exposes its value. It no longer treats posting Unicode keyboard events as evidence of insertion. Targets without a readable value still cannot be verified this way.

Finalization now uses the ending time returned by `analyzeSequence` with `finalizeAndFinish(through:)`. This follows Apple's documented structured-analysis path. It is not proof that this caused the reported intermittent failure.

The release build, six core tests, signature verification, and updated native setup render passed. The setup image was visually inspected, including the retention option and macOS 27 permission wording.

A paced stream of the existing audio fixture produced the expected transcript. Its first nonempty result arrived about 1.13 seconds after streaming started; release-to-final took about 0.098 seconds. A native pill benchmark across 20 updates measured about 46.6 ms median and 48.7 ms p95, including bitmap capture. It does not measure display presentation. These tests distinguish engine work from UI work but do not establish the cause of the user's perceived live delay. The app logs first-result and first-SwiftUI-update timings without logging dictated words.

The update was installed at `~/Applications/Voco.app` and reopened. After the user enabled Keyboard access, the LaunchServices shortcut diagnostic passed. `scripts/verify-insertion.sh` opened a new disposable TextEdit document and verified five consecutive insertions against its exact text. All five passed. Three additional paced speech runs returned the expected transcript; first-result timings were 1.12–1.15 seconds and release-to-final timings were 0.097–0.149 seconds. Physical microphone holds and the user's perceived delay still need confirmation on this update.

The user confirmed that permission grants and the menu worked, but reported the setup window being left behind after each permission. The app now brings the setup window to the front after its microphone permission request returns or a keyboard permission requested from Voco becomes granted. An unrelated external permission change does not trigger activation. The setup window explicitly stays visible on deactivation. This permission-return behavior requires a live check after enabling the updated development signature.

## Minimal status and live writing

The user changed the interaction to hold Fn for capture and Fn + Space for continuous listening, with words written directly into the field. A quick Fn tap does not enable continuous capture. The normal microphone capsule is now 50pt wide, or 80pt with a continuous-mode stop button, plus 12pt of outer padding on each side. It shows no transcript text. Native hold and continuous renders were inspected; recovery alone retains its text surface. Layout changes recenter the panel on the selected display.

The release build and 13 core tests passed. New tests cover whole-key consumption and repeat suppression for Fn + Space, pause timing, nonduplicating batches, minimal text corrections, Unicode range calculations, replacing a selected range, caret movement, document changes, and rejecting an unverified write. The installed bundle passed strict signature verification; shell syntax checks passed.

A real-engine paced fixture test initially exposed two pause-finalization problems: forcing a boundary after already final results could drop words in the following repeated phrase, and using a speculative result range could wait for future audio. The final implementation accepts already final results and allows 200 ms for natural finalization before requesting finalization through consumed input. The repeated-phrase fixture then passed, with both complete phrases returned and no extra batch when stopping.

Live edits are coalesced over 25 ms and use direct Accessibility text replacement. Each edit verifies exact document contents and caret position. Settled phrases relinquish their correction range. Clipboard-preserving insertion remains for fields without live correction support and is indicated by Buffered status. The 1.5-second pause gate also observes microphone-buffer energy, so unchanged text alone does not end a phrase during continuing audible activity.

The installed update was reopened. Its changed development signature required a new Keyboard access grant; the current diagnostic returned `Accessibility: required` and `Global shortcut: unavailable`. `scripts/verify-insertion.sh /tmp/voco-fixture.aiff` is ready to verify actual TextEdit corrections, phrase continuation, caret protection, and provisional speech writes once that grant is enabled. The earlier five-insertion check passed on the previous build; it does not prove this update's live-writing path. Physical Fn + Space behavior, ambient-noise pause detection, and live writing in browser fields remain live checks.


## Enabled permission with unavailable shortcut

On October 8, the user enabled Keyboard access but setup still displayed Allow. The installed Utter diagnostic, launched through LaunchServices with `--check-shortcut`, returned `Accessibility: granted` and `Global shortcut: unavailable`. macOS TCC logs showed a failed code requirement match for `kTCCServiceListenEvent`: the stored Input Monitoring record belonged to an older development signature. The Accessibility grant itself was valid.

Running `tccutil reset ListenEvent org.utterapp.Utter` and restarting the same installed bundle changed the diagnostic to `Accessibility: granted` and `Global shortcut: available`. No rebuild or Accessibility reset was needed. The installer now clears stale ListenEvent records when a development signature changes or an app is first installed at its destination. Its shell syntax check passed. The updated installer has not been run, to preserve the working installed signature.

The installed bundle then ran `--verify-insertion --audio-fixture /tmp/utter-fixture.aiff` through LaunchServices. All five exact TextEdit insertions passed. Live corrections took roughly 1.3–4.6 ms, phrase continuation passed, and moving the caret was rejected without changing the document. Paced real-engine audio produced 17 provisional writes with exact final text verified. First speech output arrived in about 1.14 seconds and release-to-final took about 0.24 seconds. This verifies actual Accessibility writes from speech results, but does not replace a physical Fn/Fn+Space microphone check or verify browser fields.

The source verification helper additionally checks the disposable document's initial sentinel before writing. That safety guard is source-only pending the next build; the installed bundle was intentionally left unchanged.
