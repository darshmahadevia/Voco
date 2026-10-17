# GPUI verification

The current application renders its dashboard and voice pill with GPUI. The speech controller, recognition engines, model installer, and insertion safeguards remain in Rust.

## Build and core checks

`./scripts/verify.sh` passed formatting, the runtime dependency guard, Clippy with warnings denied, all 34 tests, and the executable build. The dependency guard requires GPUI and rejects egui, eframe, and webview renderers in the normal dependency graph. Captured output is in [build.txt](evidence/build.txt).

After the placeholder contrast correction, formatting, Clippy, and the build passed again. The [correction log](evidence/contrast-build.txt) records those final checks. The independent visual reviewer scored its sole requested correction resolved after inspecting refreshed Home, Transcripts, and compact captures. No material regressions from that correction were reported.

## Native interface

The real executable completed the following command with an isolated profile:

```sh
VOCO_DATA_DIR=/tmp/voco-gpui-profile target/debug/voco --verify-ui .audit/gpui-native-final
```

The verifier waits for each native-window capture to finish before advancing. The [UI report](evidence/ui.json) records four pages, four settings panels, a compact window, recovery, and two floating-pill states. Its eleven PNGs are under `.audit/gpui-native-final`.

The captures correspond to Home, Transcripts, Statistics, Output, Models, Access, Dictation, compact Home, recovery, Listening, and Transcribing, numbered 0 through 10. Dashboard captures use 1080 by 800 points. Compact Home uses 820 by 640 points. Retina images have twice the logical dimensions. Example transcript text and microphone levels exist only in verification mode and are labeled as verification content. Usage totals remain actual profile totals.

Native assertions passed Unicode selection replacement and caret placement, changed-text refusal, composition refusal, transcript filtering and clearing, actual close-to-hide behavior, and second-instance reopening. The voice pill cannot become key or main and ignores mouse input. Showing it preserved the dashboard's actual macOS key-window identity as well as its focused practice input.

The [dashboard capture](../images/voco-dashboard.png), [compact capture](evidence/compact.png), [Listening pill](evidence/listening.png), and [Transcribing pill](evidence/transcribing.png) retain representative visual evidence.

## System insertion

`target/debug/voco --verify-insertion` passed against disposable native editors. The [insertion report](evidence/insertion.json) records a 2,200 UTF-16-unit Unicode write, selected-text replacement, changed-selection refusal, changed-field refusal, and password-field refusal.

## Limits

Microphone permission was absent for the tested executable. Accessibility permission and the shortcut monitor were available. This redesign run did not exercise live microphone dictation, physical Fn presses across applications, or model downloads and inference. Earlier engine checks are historical evidence in the [Rust migration record](../rust/verification.md).

The overlay focus check uses the dashboard as the focused editor. It does not prove behavior with every external application or fullscreen Space. The design task did not rebuild the release bundle. A later installed-bundle check is recorded below.

## Installed release bundle, October 16, 2026

`./scripts/install.sh` rebuilt the optimized executable from the GPUI source and installed it at `~/Applications/Voco.app`. Bundle checks passed the strict code-signature check, system-only dynamic dependencies, and executable UUID comparison against `target/release/voco`.

The installed executable then completed `--verify-ui` with a temporary profile. The [installed UI report](evidence/installed-ui.json) identified `"ui": "gpui"` and passed the page, settings, practice input, search, overlay focus, and close/reopen checks described above. The app opened from its installed path with `--show`. This check did not exercise microphone capture or speech inference.

## Split recording indicator, October 17, 2026

The recording indicator now pairs a 38px black voice circle with a separate 122 × 36px black status capsule and a 7px gap. The label is centered within the status capsule. Five bars show recent measured audio with nonlinear visual gain, a 35ms attack, and a 110ms release. The overlay owns this display state; microphone capture and the controller's 60ms update cadence are unchanged.

`./scripts/verify.sh` passed formatting, the dependency guard, Clippy, tests, and the debug build. The suite passed 51 tests with one ignored. Eight new waveform tests cover quiet and loud response, sample history, elapsed-time smoothing, silence settling, reduced motion, fresh state, invalid levels, and long pauses. The [build log](evidence/split-overlay-build.txt) records the results.

The rebuilt executable completed `--verify-ui` with an isolated profile. The [report](evidence/split-overlay-ui.json) confirms focus preservation, mouse transparency, practice insertion, and close/reopen behavior. The refreshed [Listening capture](evidence/listening.png) and [Transcribing capture](evidence/transcribing.png) show the actual native split layout. The verification uses fixture audio levels. Live acoustic microphone response was not exercised.

`./scripts/install.sh` rebuilt and installed the optimized app at `~/Applications/Voco.app`. Bundle and code-signature checks passed. The installed executable also completed the native UI verifier with an isolated profile; its [report](evidence/split-overlay-installed-ui.json) confirms the same overlay focus and mouse behavior. The normal app was reopened after verification.


## Persistent idle indicator, October 17, 2026

The bottom-center overlay remains visible when dictation is idle. A 7px dot and 48 × 3px line use translucent dark fills and faint white outlines. A reversible 220ms transition expands them into the existing recording circle and status capsule. Reduce Motion snaps between states, and settled idle requests no animation frames.

One native window owns both presentations. This keeps positioning, focus safety, and Space policy together. Separate idle and active windows were rejected because they duplicate those responsibilities and would require additional geometry animation to produce the same transition.

`./scripts/verify.sh` passed formatting, the runtime dependency guard, strict Clippy, all 54 tests with one ignored, and the debug build. Three transition tests cover activation and settling, reversal without a geometry jump, repeated updates, and reduced motion.

The native `--verify-ui` run captured the [idle indicator](evidence/idle.png), Listening, and Transcribing states. Its [report](evidence/idle-overlay-ui.json) confirms persistent settled idle, preserved keyboard focus, mouse transparency, close and reopen behavior, and the existing practice-input checks. The verifier enters an actual native fullscreen Space, checks that the overlay is outside that Space, exits fullscreen, and checks that the idle overlay returns. The native policy also disallows fullscreen tiling. Split View and applications that simulate fullscreen with ordinary borderless windows were not exercised.

Microphone levels in these screenshots are fixtures. This change did not exercise live microphone capture or speech inference.

`./scripts/install.sh` rebuilt the optimized app and installed it at `~/Applications/Voco.app`. Bundle and strict code-signature checks passed. The installed executable completed the same native verifier with an isolated profile; its [report](evidence/idle-overlay-installed-ui.json) confirms persistent idle, native fullscreen exclusion and return, focus preservation, and mouse transparency. The normal app was reopened after verification.
