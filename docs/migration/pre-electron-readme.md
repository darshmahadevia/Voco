# Voco

Hold Fn or Globe to dictate English directly into your text field. Release to stop. Press Fn or Globe + Space to toggle continuous listening, with phrases settled after a pause. The bottom-center pill shows only microphone status and a stop button in continuous mode.

Voco is a native macOS app with MIT-licensed source code. Apple's proprietary SpeechAnalyzer model runs transcription on your Mac. There is no transcription subscription or API key. Setup may download English speech assets once.

## Build and run

You need an Apple Silicon Mac with macOS 26 or newer and Swift 6.2 or newer with the macOS 26 SDK. Xcode or the corresponding Command Line Tools provide the compiler and SDK.

From this directory, run:

```sh
./scripts/install.sh
open ~/Applications/Voco.app
```

The build script creates a locally signed app in `~/Library/Caches/Voco/Build/Bundle` and links it at `build/Voco.app`. It keeps the app and compiler intermediates outside synced folders, where Finder metadata can prevent signature verification. Set `VOCO_BUILD_DIR` to use another local build directory.

The install script places the app in `~/Applications/Voco.app` so you can select it in macOS permission settings. It builds the app before installing it, so you can run the install script alone.

When an update changes this development build's designated signing requirement, the installer closes the old installed process and resets Voco's keyboard and microphone permissions. Enable Keyboard access and prepare English speech again after that update. An unchanged requirement preserves the existing grant. Set `VOCO_SIGNING_IDENTITY` to a valid signing identity to use it instead of ad-hoc signing.

Voco uses its own bundle identifier, `org.vocoapp.Voco`. Upgrading from a build that shared Utter's identifier requires granting access to the new Voco entry. The installer leaves Utter's permissions unchanged and copies Voco's talk key, pause, and transcript retention settings once. A first install also clears stale Voco permission records left by a previously deleted build.

## Set up dictation

1. In Voco, click **Prepare**. Grant microphone access and wait for English transcription to become ready.
2. In Voco's **Keyboard access** row, click **Allow** and follow the macOS prompt. **Open Settings** reopens the permission page without prompting again. Enable Voco in **System Settings > Privacy & Security > Device Control and Data Access** on macOS 27. On macOS 26, the same page is called **Accessibility**. If Voco is missing, click **+** and select `~/Applications/Voco.app`. **Show Voco in Finder** reveals that app for you. If access is enabled but the shortcut is unavailable, click **Restart Voco**.
3. In **System Settings > Keyboard**, set **Press Globe key to** to **Do Nothing**. Disable an Apple Dictation shortcut that uses the same key.
4. Close the Voco setup window and click a text field in another app.
5. Hold Fn or Globe until the small microphone pill appears, then speak. Words appear in your field while you talk. Release to stop and apply final corrections.

For continuous listening, press **Fn or Globe + Space**, release the keys, and speak. Words appear immediately as results arrive. A pause settles the current phrase; the default is 1.5 seconds and is adjustable in Settings. Press the shortcut again or click the pill's stop button to finish. A quick tap on Fn alone does not start continuous listening.

Escape stops capture and keeps words already written. Using the held key in another shortcut cancels capture. Left Option or right Option can replace the hold key; continuous listening remains Fn + Space.

If macOS requests an app restart after a permission change, quit Voco from its waveform menu-bar icon and open it again.

Voco uses AppKit keyboard monitors for the hold key and an active event filter to consume Fn + Space. These use the Keyboard access grant. There is no separate Input Monitoring setup step. [Apple's event-monitor guide](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/EventOverview/MonitoringEvents/MonitoringEvents.html) and [event-tap documentation](https://developer.apple.com/documentation/coregraphics/cgevent/tapcreate(tap:place:options:eventsofinterest:callback:userinfo:)) describe the underlying APIs.

## Live writing

Voco corrects only the range it inserted, leaving surrounding text intact. It validates the field, document contents, and caret before every edit. Moving the caret, changing the document yourself, or switching fields stops automatic writing. Pauses commit the current phrase so subsequent corrections apply to the new phrase.

Live correction requires a native field that exposes working writable text and selection. Web editors, including Electron chat composers, use normal paste after release or a pause; the pill says **Buffered**. This lets the editor receive its input events and update its own state. A native field that rejects or ignores its first live edit also switches to Buffered when Voco verifies that no words were inserted. Speech processing still runs locally. Live edits use text replacement directly and do not use the clipboard.

## Recover a transcript

If the focused field changes or insertion fails, Voco keeps your words in the pill. Click **Copy text** and paste them manually. If the engine finishes without final words, the preview stays available to copy.

Click the waveform menu-bar icon and choose **Settings…** to reopen setup. Opening Voco again also opens settings. **Keep last transcript available to copy** is enabled by default. It keeps one transcript in memory, including failed or cancelled attempts, until you quit. Turn it off to clear that saved transcript. **Copy last transcript** is available in both settings and the menu.

Insertion uses Accessibility text replacement in supported native fields and standard paste in web editors and other unsupported fields. The paste temporarily places your words on the clipboard, then restores its previous contents unless another app or you change it during insertion. Where the destination exposes its text, Voco checks that it changed instead of silently treating event dispatch as success. Replacing a selection with identical words also counts as insertion when the caret confirms the replacement. If a live edit changes any text but cannot be verified, Voco offers recovery instead of retrying the whole phrase and duplicating words.

Automatic insertion depends on the target app's Accessibility and keyboard support. Password fields are rejected. Voco does not press Return or submit forms.

## Verify a build

Run the core behavior tests and transcript recovery check:

```sh
./scripts/test.sh
./scripts/check-recovery.sh
./scripts/check-focus.sh
./scripts/check-insertion.sh
./scripts/check-permissions.sh
./scripts/check-install.sh
```

The recovery check compiles the actual app model with a test extension, simulates a canceled session followed by a quick key tap, and verifies the full saved transcript. It does not start microphone capture or require Keyboard access. GitHub Actions runs these checks and builds the signed release app for pushes to `main` and pull requests.

The focus check exercises the actual cursor-resolution code against simulated Accessibility responses, including Electron's initially inactive tree, delayed focus, app and field changes, password fields, and cancellation. It does not require privacy permissions or prove live insertion in T3 Code.

The insertion check drives the actual live writer, buffered insertion, and app model with simulated editor responses. It covers web editors that advertise unsupported writes, rejected and ignored native writes, failed selection changes, unreadable write results, Unicode, identical selected text, clipboard restoration, pause spacing, and preventing duplicate insertion. It runs without privacy permissions and does not replace checking the actual destination app.

The permission check drives the actual app model with simulated macOS permission and keyboard-monitor responses. It verifies a single prompt, the Settings retry, restart after a failed monitor start, approval, revocation, and reapproval. The real macOS grant must still be enabled by the user.

The installer check runs the actual installer in a disposable directory with signing and permission-reset command fixtures. It verifies migration from the shared Utter identity, unchanged installs, stable signing requirements, changed requirements, and rejection of unrelated apps.

Render the native setup, listening, and recovery views:

```sh
build/Voco.app/Contents/MacOS/Voco --render-previews
```

The previews are written to `.impeccable/review/`. Their sample transcript is illustrative.

To exercise the real speech engine with a local audio file:

```sh
build/Voco.app/Contents/MacOS/Voco --transcribe-file /absolute/path/to/audio.aiff
```

This prints the transcript and elapsed time. It may download missing English assets. File transcription does not test microphone access, a physical Fn key, or insertion into another app. See [the verification record](docs/verification.md) for checks performed on this version.

Check whether macOS allows the installed app to start its shortcut monitor:

```sh
./scripts/check-shortcut.sh
```

Look for `Accessibility: granted` and `Global shortcut: available`. The script launches through `open` so macOS checks Voco's permission rather than attributing the request to your terminal. It exits with a failure if the monitor is unavailable. This does not exercise a physical key hold.

After Keyboard access is enabled, run `./scripts/verify-insertion.sh` to open a new disposable TextEdit document. It verifies five insertions, live corrections, Unicode handling, phrase continuation, and rejection of caret movement against the actual document. Leave the keyboard and mouse idle while it runs. It leaves the disposable document open.

To verify another app, type a disposable sentinel such as `Voco disposable insertion check. ` into an empty draft and leave the caret at its end. Run `./scripts/verify-focused-insertion.sh 'Voco disposable insertion check. '` while that app remains focused. The installed app refuses to write unless the focused text exactly matches the supplied sentinel and the caret is at its end. It verifies three insertions, including Unicode and phrase continuation. It does not press Return or send the draft. Clear the disposable draft after the check.

To check the actual restart action, quit Voco and run `./scripts/check-restart.sh`. It launches the installed signed app, invokes the same relaunch action as setup, verifies the original process exits, and leaves one new Voco process running.

Pass a local audio fixture, such as `./scripts/verify-insertion.sh /tmp/voco-fixture.aiff`, to check live speech updates into that document as well. `--verify-pauses /absolute/path/to/audio.aiff` streams the same fixture twice with silence between phrases and verifies that finishing does not repeat inserted words.

`--transcribe-stream /absolute/path/to/audio.aiff` feeds a file at roughly real-time speed through the microphone's conversion path and reports first-result and release-to-final timings. `--measure-ui` measures native pill updates and bitmap rendering. These are diagnostics, not end-to-end microphone or display latency measurements.

## Distribution

Local builds and sharing the source are free. The build script defaults to ad-hoc signing. It does not create a notarized public download. Apple's Developer ID signing and notarization require developer-program membership. [Apple's Developer ID guide](https://developer.apple.com/developer-id/) describes that distribution path.

See [the architecture](docs/architecture.md) for session ownership and the engine comparison.
