# Project audit, October 15, 2026

## Intent

Voco should provide reliable local dictation with little maintenance. Capture, recognition, safe insertion, recovery, and straightforward updates justify complexity. Retired recognition behavior and duplicate bookkeeping do not. Prefer deletion, then simplification, before optimization or automation.

## Reviewers

GPT-6-Astra and GPT-6-Sol independently inspected the project read-only. The interrogate skill's default Claude and Grok providers were unavailable. The lead traced callers, reproduced the model activation bug, implemented the changes, and verified the resulting app. Both reviewers checked the resulting changes and reported no blockers.

## Act on

- Deleted partial-transcript polling from all three engines. Production already records and finishes once. Removed the streaming CLI, its obsolete polling benchmark, provisional transcript storage, and tests of those retired behaviors.
- Deleted duplicate synchronous loading and finalization APIs, Parakeet result boxes, and unused engine descriptors. File and microphone diagnostics now use production's asynchronous loading and final inference. Kept final-inference cancellation and queued-result suppression checks.
- Deleted the CLI-only full Whisper v3 variant and its parameters. Whisper Turbo remains available alongside Moonshine and Parakeet, as specified by the product.
- Derived the selected model's status directly from the model catalog. Deleted the synchronization method and its callers. Fixed activation so a missing previous model stays missing, and rollback reloads only an engine that was previously ready.
- Deleted the unused stop command and the native restart handler that Electron intercepts.
- Deleted the extra build wrapper, its unused app link, and unused Instrument Serif and Pixelify Sans assets and licenses. Normal builds now consume committed icons. Icon generation remains an explicit step when editing the brand source, avoiding uncommitted asset changes during a push.
- Moved the hook test into the existing Vitest run, removing the separate JavaScript test command.
- Wait for the old app to quit before replacing its bundle. Preserve recovery text if copying to the clipboard fails.

## Consider

Build caches and the installed app are shared across checkouts. Concurrent builds and installations still need isolation or serialization. This audit did not reproduce a collision, and adds no new orchestration system.

The orphaned audio-tap fixture has no current runner and supplies an invalid, unloaded engine. It is not evidence of current test coverage. Its audio-conversion assertions could be revived with a working fixture, but that is separate verification work.

## Dismissed

Removing Electron, a supported speech engine, cleanup modes, or statistics would change the product without evidence that the remaining version meets users' needs. Preserve insertion verification, focus checks, session identity, cancellation, model checksums, and rollback because they protect actual failure paths. Historical migration documents remain useful records.

## Agreement

Both reviewers identified redundant model state and update lifecycle problems. Their independent findings about retired decoding and unused Whisper configuration led to one smaller final-transcription interface. The lead accepted concrete deletions and correctness fixes, and deferred speculative feature cuts and new automation.

## Verification

- TypeScript checking and 28 JavaScript tests pass, including hook selection, dirty checkouts, installation failures, and existing-hook preservation.
- Production Swift and Electron builds, native JSONL protocol checks, deferred dictation fixtures for all three engines, and shortcut-monitor checks pass.
- The built renderer passes 52 layout and onboarding/search scenarios.
- The new model activation regression failed before the fix. It now covers successful and failed activation with both missing and previously loaded engines, plus derived model status.
- Old and new helpers return exactly the same transcript for one fixed speech recording on each of the three cached models. This establishes fixture parity, not general recognition quality.
- Whisper cancellation during inference, suppression of a queued final result, and subsequent recognition pass. One existing deadline assertion failed while heavy inference checks ran concurrently; the deferred suite passed when rerun alone. Its fixed waits remain timing-sensitive.
- Updating a running installed app exits the old PID and launches a new PID. Installed JavaScript, brand assets, native helper UUID, and strict deep signatures match the build. The packaged desktop passes navigation, permission return, and ready-model checks. The installed helper captures microphone audio; that check used silence and does not establish recognition of live speech or a physical Fn press.
