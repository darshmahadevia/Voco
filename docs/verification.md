# Verify Voco

Run `./scripts/verify.sh` for formatting, Clippy, tests, and a debug build. Run `VOCO_VERIFY_UI=1 ./scripts/verify.sh` to render the four dashboard pages through the real executable. Run `./scripts/verify-bundle.sh` after packaging.

Use `cargo run -- --verify-insertion` for disposable native text insertion checks. Use `cargo run -- --diagnostics` to inspect permissions and installed model files.

For recognition, prepare a mono 16 kHz WAV recording and run `VOCO_VERIFY_AUDIO=/path/to/audio.wav ./scripts/verify.sh`. All three models must already be installed.

The [Rust migration verification record](rust/verification.md) records completed checks and limitations. Physical Fn/Globe behavior, permission revocation, fullscreen apps, and acoustic capture require live hardware checks. A screenshot or successful compile does not prove those behaviors.
