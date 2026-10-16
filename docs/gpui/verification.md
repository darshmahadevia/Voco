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
