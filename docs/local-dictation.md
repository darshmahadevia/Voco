# Local dictation and output quality

Voco is an applied AI project for English dictation on Apple Silicon Macs. Its pipeline captures speech, runs a local speech model, optionally cleans the transcript, and inserts the result into the original field. Local processing and recoverable text take priority over a latency promise. Recognition and cleanup can still make mistakes.

## Choose an output mode

Open **Settings → Output quality**. Changes apply to the next capture. Fast remains the default for existing installations.

- **Fast** pastes the selected speech model's transcript without cleanup.
- **Balanced** combines recognition with local rules for fillers and spoken restarts. It does not run a language model.
- **Accurate** requests conservative cleanup from Apple's on-device language model. It allows punctuation and capitalization changes and the same limited deletions as Balanced. It takes an extra processing pass. The name describes the intended use, not a measured accuracy advantage.

Choose the speech model separately. Voco does not claim a model ranking without evaluation on representative audio. All output modes use the selected engine.

Balanced removes standalone `um`, `umm`, and `uh`. A standalone `never mind` or `nevermind` discards the current sentence before the phrase. Earlier completed sentences remain. Quoted occurrences are preserved. Use Fast for literal dictation of these phrases. Sentence boundaries come from the speech model, so inspect the result if its punctuation is wrong.

For example, `Keep this. Send it Tuesday, never mind, send it Friday.` becomes `Keep this. send it Friday.` in Balanced. This mode does not rewrite grammar or infer that every correction phrase is a command.

## Recover the original

With **Keep recent transcripts** enabled, Home exposes **Original speech transcript** when cleanup changed the latest transcript. Expand it to inspect and copy the original. Both versions stay in memory until quit. Turning retention off clears them.

Accurate keeps the original if the local model is unavailable, the input exceeds the cleanup limit, generation fails, exceeds its 20-second deadline, or validation rejects the result. A notice explains the fallback. Rejected output is never inserted. Recognition has a separate 120-second deadline. Escape cancels pending processing, and session identity prevents a late result from inserting into a later dictation.

## On-device model requirements

Accurate uses the FoundationModels `SystemLanguageModel` in the native helper. Apple Intelligence must be supported, enabled, and ready. Settings reports availability. Voco does not send cleanup requests to a cloud service or start a hidden model download. Apple's system manages its own model installation. Speech-model downloads remain explicit in Voco setup.

Apple documents [the on-device model and availability states](https://developer.apple.com/documentation/foundationmodels/systemlanguagemodel) and [text generation](https://developer.apple.com/documentation/foundationmodels/generating-content-and-performing-tasks-with-foundation-models).

## Evaluate before claiming accuracy

Run `./scripts/check-transcript-polisher.sh` for fixed text cases and `./scripts/check-transcript-polisher.sh --smoke` for an actual local generation check. The fixed cases check allowed edits and fallback behavior. They do not measure recognition accuracy.

For a recognition evaluation, use consented audio with literal reference transcripts, including accents, background noise, names, numbers, negations, and restarts. Compare raw and cleaned results separately. Report word error rate, meaning-changing edits, insertion failures, and processing time with the hardware and model versions. Keep evaluation audio and transcripts out of the repository unless they are explicitly licensed for publication. No comparative accuracy claim has been established by these implementation checks.
