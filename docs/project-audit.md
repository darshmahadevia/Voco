# Project audit, October 10, 2026

## Intent

Voco captures English speech locally and inserts one completed transcript into the original text field. Reliability, focus safety, recoverable failures, and offline recognition justify complexity. Code for abandoned insertion behavior does not.

## Reviewers

Two independent gpt-6.1-sol reviewers audited the current project read-only. The interrogate skill's default Claude and Grok providers were disabled. The lead checked callers, reproduced the retention bug, and verified the changes.

## Act on

- Both reviewers found incremental commitment bookkeeping used only by its legacy smoke test. Deleted committed IDs, prefix selection, insertion tracking, and separator logic. Dictation now stores its completed text directly; microphone diagnostics keep only their latest transcript snapshot.
- Both found a window-mode command that only stored a value. Deleted the renderer effect, preload method, IPC handler, schema, and verifier's no-op toggles. The desktop check reads actual window dimensions and constraints.
- Reviewer A found premature transcript retention during insertion. A timer snapshot could add the words to history, then completion added them again when the session count advanced. The new delayed-insertion assertion failed before the fix. Retention now updates on completion or recovery, preserving incomplete-final recovery.
- Reviewer B found speech-line IDs and timestamps with no readers after commitment removal. Deleted them from the internal structure, engines, and fixtures. Also removed the coordinator's single-call capture wrapper and output lock; its output methods already run on the main actor.
- Reviewer A found that every listening snapshot claimed hold mode, including continuous capture. No UI consumes that field. Deleted it rather than expanding the contract.
- Both found obsolete product and architecture requirements. Corrected the current contract. Deleted the benchmark guide and two related strategy documents because their runner, analysis script, and result artifacts are absent and their production assumptions predate complete insertion. Git history retains them.

## Consider

The renderer and stylesheet are large. Size alone does not justify a rewrite, and this review found no behavior-preserving deletion large enough to warrant changing their structure now.

## Noted

The available reviewers share a model, so their agreement does not provide model diversity. Automated shortcut checks do not prove a physical Fn key press.

## Dismissed

Deleting Electron, reducing the app to one speech engine, or removing statistics would change supported product behavior. The current evidence does not justify those cuts. Focus validation, complete-write checks, clipboard restoration, session identity, and model activation rollback address actual failure paths and remain.

## Verification

Production TypeScript and Swift builds, 25 TypeScript tests, transcript smoke checks, all three deferred-dictation fixtures, shortcut-monitor checks, and native JSONL protocol checks pass. The delayed-insertion regression fails on the premature retention behavior and passes after its deletion.
