# Voco

Speak into the app you're using. Voco turns your voice into text on your Mac.

Hold **Fn** or **Globe**, speak, and release. Voco transcribes locally and inserts your words at the cursor. **Fn + Space** starts and stops continuous dictation. **Escape** cancels recording or pending transcription.

Voco is a Rust application. Its dashboard uses egui. Rust bindings call macOS frameworks for the menu bar, permissions, shortcuts, the recording panel, and text insertion. The app has no Electron, browser UI, Node.js, or Swift helper.

## Build and run

Voco requires an Apple Silicon Mac with macOS 26 or newer, Rust 1.92 or newer, Apple's Command Line Tools, and CMake. Speech inference dependencies include native C and C++ libraries compiled or fetched by Cargo. A first build needs internet access.

```sh
cargo run -- --show
```

Build a signed local application bundle and install it.

```sh
./scripts/package.sh
./scripts/install.sh --built
open ~/Applications/Voco.app
```

Without `--built`, the installer builds first. Local builds use your configured signing identity, or ad hoc signing. They are not notarized. See [development](docs/development.md).

Normal launch starts in the menu bar with the dashboard hidden. Choose **Open Dashboard** to open it. Closing the dashboard keeps Voco running. Choose **Quit Voco** from the menu bar to exit.

## Set up dictation

1. Download a speech model in the dashboard.
2. Allow Microphone and Accessibility access for **Voco**. There is no separate helper to approve.
3. Set **Press Globe key to** to **Do Nothing** in macOS Keyboard settings. Use a different shortcut for Apple Dictation.
4. Click the practice field and try holding Fn. Then dictate into a text field in another app.

Voco supports Moonshine Medium Streaming, Parakeet TDT 0.6B v2, and Whisper Large v3 Turbo in English. Model downloads use the internet. Recognition works offline after installation.

Existing Moonshine and Whisper downloads are reused. The Rust Parakeet runtime needs a separate ONNX download. Existing CoreML Parakeet files stay untouched.

Voco inserts the final transcript once. It refuses insertion if the destination app, text field, selection, or readable text changes. It does not write into password fields, press Return, or send messages. If insertion fails, copy the complete transcript from recovery. Review your words before sending them.

## Output and privacy

**Fast** keeps the speech model's transcript. **Balanced** removes fillers and spoken restarts with local rules while protecting literal text. **Accurate** currently uses Balanced cleanup and displays a notice. Apple's Swift-only FoundationModels formatting is unavailable in the Rust build.

Audio and transcript history stay in memory. Voco never saves recordings or transcripts to disk. Turning off **Keep recent transcripts** clears retained history immediately. Failed insertion text remains available for recovery. Continuous recording stops at ten minutes and transcribes the captured audio.

Settings and usage totals live in `~/Library/Application Support/Voco/settings.json`. Model files live in the adjacent `models` directory. The app migrates previous local preferences and usage totals on its first run.

## Verify

```sh
./scripts/verify.sh
VOCO_VERIFY_UI=1 ./scripts/verify.sh
cargo run -- --diagnostics
```

The [verification record](docs/rust/verification.md) distinguishes tested behavior from hardware checks. See [architecture](docs/architecture.md) for module ownership and cancellation.

## License

Voco application code uses the [MIT License](LICENSE). Speech engines, model weights, and Manrope have their own licenses. The app bundles [third-party notices](Resources/licenses).
