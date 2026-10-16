# Rust migration

The target is one Rust application executable. React, Electron, Node, and the Swift helper leave the runtime and build. Apple frameworks and native speech inference libraries remain dependencies.

The original TypeScript baseline passed all 28 tests and type checking before migration.

## Design and workflow

1. Define model IDs, output modes, the shortcut state machine, and session states in Rust. Verify shortcut behavior before integration.
2. Implement direct macOS permission, focus, insertion, and shortcut bindings. Capture microphone audio through CPAL.
3. Implement local speech runtimes and verified model installation. Keep downloaded model storage under Application Support/Voco.
4. Implement the dashboard, transcript recovery, settings, usage statistics, tray navigation, and recording overlay in egui.
5. Replace packaging, installation, and verification scripts. Remove the previous application after the Rust executable builds and passes its checks.
6. Exercise the executable and packaged app, audit the diff, and commit each verified unit.

`domain::Session` owns the recording lifecycle. `gesture::HoldGesture` maps keyboard events to actions. The UI thread owns session transitions and insertion. Inference and downloads run on workers, and generation IDs reject stale completions after cancellation.

Two UI designs are under consideration. An AppKit implementation uses Rust Objective-C bindings for both controls and platform integration. An egui implementation keeps UI state and rendering in Rust and reserves Objective-C calls for macOS behavior. egui avoids a large custom Objective-C class hierarchy and provides testable, portable UI logic.

## Completion checks

The Rust build must contain no React, Electron, or Swift application runtime. Formatting, clippy, and tests must pass. The packaged executable must open, stay in the menu bar when its dashboard closes, and expose all three local engines. Dictation must capture a target before recording, refuse insertion after focus changes, and discard cancelled inference results.

Hardware permissions and actual inference require separate runtime checks. A successful compile does not prove them.
