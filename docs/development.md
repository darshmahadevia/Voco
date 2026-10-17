# Develop Voco

Install Rust 1.92 or newer, Apple's Command Line Tools with Swift 6.2 and the macOS 26 SDK or newer, and CMake on an Apple Silicon Mac running macOS 26 or newer.

## Run

```sh
cargo run -- --show
```

Run without `--show` to start hidden in the menu bar. A second `--show` invocation opens the running instance's dashboard.

Use an isolated profile to test setup without changing normal preferences.

```sh
VOCO_DATA_DIR=/tmp/voco-development cargo run -- --show
```

The profile contains settings, usage totals, model downloads, and a process lock. Audio and transcripts are never persisted.

## Check changes

```sh
./scripts/verify.sh
```

This checks formatting, Clippy warnings, tests, and the executable build. Add `VOCO_VERIFY_UI=1` to launch the real app with an isolated profile and save four rendered screenshots and a JSON report.

```sh
cargo run -- --verify-insertion
cargo run -- --diagnostics
cargo run -- --transcribe moonshine /path/to/mono-16khz.wav
cargo run -- --cleanup balanced 'Um, send it today.'
```

Insertion verification creates disposable native fields and requires Accessibility permission. Recognition requires the selected model to be installed. The input WAV must contain mono 16 kHz PCM or float samples. `--download moonshine`, `--download parakeet`, and `--download whisper` install models explicitly.

Set `VOCO_VERIFY_AUDIO` to a WAV path when running `scripts/verify.sh` to transcribe through all three engines. Use `scripts/verify-inference.sh` with both `VOCO_VERIFY_AUDIO` and `VOCO_VERIFY_EXPECTED_TRANSCRIPT` to compare the recognized words against an expected sentence across all three engines. This does not test physical Fn key presses or acoustic microphone capture.

## Update the installed app

Pulling source does not replace the installed app. To rebuild and install the current checkout:

```sh
git pull --ff-only
./scripts/install.sh
open ~/Applications/Voco.app --args --show
```

The installer preserves settings and models. It replaces the application at `~/Applications/Voco.app` and moves the previous bundle to the Trash.

## Package and install

```sh
./scripts/package.sh
./scripts/verify-bundle.sh
./scripts/install.sh --built
```

Packaging creates `release/Voco.app`, backed by `~/Library/Caches/Voco/Rust`. Add `dmg` to create a disk image. The bundle contains one Rust application executable with a statically linked Swift FoundationModels bridge, its icon, fonts, and license notices. Inference libraries are static, and the Metal library is embedded.

`VOCO_CODESIGN_IDENTITY` selects the signing identity. Otherwise packaging reads `~/Library/Application Support/Voco/signing-identity`, then falls back to ad hoc signing. The existing `scripts/setup-local-signing.sh` configures a local identity. Local builds are not notarized.

The installer verifies the bundle, quits an existing installed Voco process, moves the previous application into the Trash, and installs the new bundle. It preserves model downloads and settings.

`./scripts/setup-push-update.sh` enables the existing local pre-push update hook. `VOCO_SKIP_LOCAL_UPDATE=1 git push` bypasses that local update.
