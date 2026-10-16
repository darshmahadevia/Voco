# Native dictation design

Historical document for an earlier Voco implementation. Commands and design details below may refer to removed code. See the [current README](../../README.md), [architecture](../architecture.md), and [development guide](../development.md).

Voco uses a native menu-bar shell and Apple's on-device speech engine. The user chose this approach over a bundled open-source speech engine for the first version.

## User flow

Click a text field. Hold Fn or Globe for 140 milliseconds to capture and write live text. Release to stop and apply final revisions. Fn + Space toggles continuous listening; pauses settle phrases while the microphone keeps running. Escape stops capture, preserving text already written. A minimal nonactivating microphone pill remains at the bottom center of the active display.

Setup handles the microphone, Accessibility, and the first English model download before normal dictation. Accessibility enables the global keyboard monitor and text insertion together. The default key can be changed to either Option key.

## Ownership

`AppModel` owns the session lifecycle, setup state, and live writer. Each session has an ID. Completion and preview callbacks from an old session cannot change the current session or insert text. Live writes are coalesced over 25 ms, and normal microphone status does not observe transcript changes.

`SpeechSession` owns the microphone engine, audio conversion, analyzer, and result tasks. It accepts audio through a bounded stream. On release it stops capture, drains input, finalizes recognition, and returns a transcript snapshot. Pause finalization leaves the audio engine running. It uses naturally final results when available and allows 200 ms for natural finalization before requesting finalization through consumed input. Audio is never saved to disk.

`ShortcutMonitor` uses AppKit global and local event monitors for modifier changes. A separate active CGEvent filter consumes Fn + Space, including its key-up and repeats, and queues one continuous-mode toggle. Ordinary keyboard input passes through. Both mechanisms use Keyboard access. `ContinuousShortcut` models the consumed key lifecycle; `HoldGesture` models hold and combination cancellation.

`FocusTarget` snapshots the frontmost process and focused Accessibility element before capture. Insertion requires both to match and rejects password fields. It checks the focused element's ancestors for an `AXWebArea`. Web editors use a clipboard-preserving normal paste so their input handlers receive the edit. Supported native fields use selected-text replacement with paste fallback. Insertion checks for a text change where the destination exposes its value; replacing identical selected words is verified through the collapsed caret instead.

The paste key-up releases its synthetic Command modifier. Keeping Command set on that event leaves it in the combined session state and causes the next buffered phrase to fail the held-shortcut guard.

Each target capture requests `AXManualAccessibility`, which exposes the Accessibility tree in Electron apps such as T3 Code. Native apps can reject this unsupported attribute without affecting lookup. If the first focused-element read is missing, startup retries that captured process for up to 300 ms before opening the microphone. The first resolved field becomes the session target. Later validation never enables accessibility or recaptures a different field. This follows [Electron's documented macOS integration](https://github.com/electron/electron/blob/main/docs/tutorial/accessibility.md).

`LiveTextWriter` validates a native focused field and captures readable document text and the selected range. `LiveTextBuffer` plans minimal replacements using common prefixes and suffixes at grapheme boundaries, while ranges use UTF-16 as required by Accessibility. Every edit checks the expected document and caret, updates only the owned range, explicitly restores the caret to its end, and verifies the actual result. Settled phrases relinquish their range. Web editors use buffered insertion from the start. A native editor that rejects or ignores the first live replacement can switch to buffering only after the original document and caret have been verified or restored. `AppModel` handles this transition in preview, pause, and release paths. An unreadable result, partial write, failed correction after words have appeared, or unexpected document or caret change stops writing instead of retrying a potentially duplicated phrase.

`Transcript` replaces overlapping provisional segments with new results and joins segments in time order. Its time watermark excludes already committed phrases. `PauseGate` waits until both audible activity and transcript revisions have settled, and prevents repeated empty insertions during silence. Audio activity uses converted-buffer energy; it is a simple threshold, not semantic speech detection.

## Synthesis decision

The native SpeechAnalyzer candidate is the base. An independent comparison scored it higher for simplicity and latency potential than a separate whisper.cpp worker. Both candidates keep speech local and avoid usage fees.

The worker candidate contributed explicit session IDs and cancellation rules. Its C++ bridge, rolling-window inference, and model management are deferred because the user selected Apple's engine. Concrete session objects hide the audio pipeline without introducing a plugin protocol before a second implementation exists.

## Accepted tradeoffs

- Apple controls the model and its supported hardware and languages.
- Live words may change while recognition improves. Automatic edits stop if the user changes the caret or document.
- A prepared analyzer retains model resources for faster subsequent sessions.
- The pill preserves input focus. If focus changes, the user copies the transcript manually.
- A local ad-hoc signed build costs nothing. Public Developer ID signing and notarization require Apple program membership.

## Verification

Core tests exercise hold, release, combination cancellation, Fn + Space consumption, pause boundaries, transcript revisions, Unicode edits, and caret protection. Native view previews verify the setup, hold, continuous, and recovery layouts. Paced file transcription exercises the speech pipeline independently of microphone permission. The insertion verification opens a disposable TextEdit document and reads actual values after buffered insertion and live corrections. An optional fixture drives live speech into that field. Physical microphone and shortcut checks still require the user's keyboard and grants.

Record first-preview and release-to-final latency on cold and warm sessions before claiming a speed benchmark.

## Keyboard permission correction

The initial setup required a separate Input Monitoring grant. The user could not add Voco to that permission list. This requirement blocked setup even though the app already needed Accessibility for text insertion.

AppKit's global keyboard monitor supports trusted Accessibility apps. The current design uses that monitor and removes the separate Input Monitoring requirement. A local monitor covers events in Voco itself. The installed app lives in `~/Applications`, and setup can reveal it in Finder for manual addition to Accessibility.

`--check-shortcut` exercises the actual authorization check and monitor installation. macOS grant changes still require a human. A passing monitor check alone does not prove physical Fn delivery.

## Sources

- [Apple's SpeechAnalyzer walkthrough](https://developer.apple.com/videos/play/wwdc2025/277/)
- [SpeechTranscriber documentation](https://developer.apple.com/documentation/speech/speechtranscriber)
- [Argmax open-source speech SDK](https://github.com/argmaxinc/argmax-oss-swift)
- [Apple Developer ID distribution](https://developer.apple.com/developer-id/)
- [Apple's event-monitor permission guide](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/EventOverview/MonitoringEvents/MonitoringEvents.html)
