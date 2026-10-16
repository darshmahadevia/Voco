# Rust migration

Historical record of the initial Rust port, which used egui. GPUI has since replaced egui. See the [current architecture](../architecture.md) and [GPUI verification](../gpui/verification.md).

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

The design comparison considered two UI implementations. An AppKit implementation uses Rust Objective-C bindings for both controls and platform integration. An egui implementation keeps UI state and rendering in Rust and reserves Objective-C calls for macOS behavior. The selected design uses egui for the dashboard and a Rust-controlled nonactivating AppKit panel for recording. This preserves the custom dashboard without a large Objective-C class hierarchy. The practice field uses egui state directly, so its correctness does not depend on an Accessibility round trip into the same process.

## Completion checks

The Rust build must contain no React, Electron, or Swift application runtime. Formatting, clippy, and tests must pass. The packaged executable must open, stay in the menu bar when its dashboard closes, and expose all three local engines. Dictation must capture a target before recording, refuse insertion after focus changes, and discard cancelled inference results.

Hardware permissions and actual inference require separate runtime checks. A successful compile does not prove them.

## Applied principles

Model the Domain put sessions, model IDs, shortcut state, and native versus practice targets into typed Rust structures. Foundational Thinking established these types and behavioral fixtures before the desktop integration. Sequence Work into Verifiable Units separated core recognition, platform integration, the dashboard, and packaging into checked commits.

Separate Before Serializing Shared State gave each implementation worker distinct files. Never Block on the Human kept reversible implementation moving after the user clarified the full Rust scope. Type System Discipline kept native and practice insertion targets distinct.

Build the Lever produced repeatable build, bundle, inference, and running-UI checks. Prove It Works required real transcription, native field writes, and the packaged application. The verification record distinguishes these results from microphone and hardware checks that remain unavailable.
