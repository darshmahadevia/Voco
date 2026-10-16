# Cleanup verification before the Rust migration

Historical record for the retired Electron and Swift app. Its commands and FoundationModels results do not apply to the current app. See [current cleanup verification](../cleanup-verification.md).

The cleanup polish replaces filler deletion across the whole transcript with edits outside protected text. Accurate now formats the Balanced result and keeps that result when the model fails or its output is rejected.

## Reproduce the checks

```sh
./scripts/evaluate-cleanup.sh
./scripts/evaluate-cleanup.sh --model
./scripts/check-transcript-polisher.sh
./scripts/check-deferred-dictation.sh
npm run typecheck
npm test
npm run verify:compact-ui
```

The acceptance corpus has 49 fixed inputs and expected Balanced outputs. It checks Fast preservation, Accurate fallback when the model is unavailable or throws, and stable output when cleanup runs twice. Sixteen candidate edits must be rejected, including changed flags, paths, email addresses, quotations, numbers, negations, paragraph boundaries, leading decimals, and moved currency signs. The expected values live in `native/Tests/Fixtures` and the runner is `native/Tests/CleanupEvaluation.swift`.

## Observed local results

Before the change, executable probes produced `I, need this.` from `I, um, need this.`, `Send it,.` from `Send it, um.`, and a damaged URL from `https://example.com/um`. Updated fixture outputs preserve the URL and produce `I need this.` and `Send it.`.

The original Accurate flow sometimes rejected a model result and restored fillers or a discarded phrase. The new flow keeps deterministic cleanup in that case, including on the coordinator's cleanup deadline. The original speech transcript remains separate for recovery.

Actual FoundationModels generation on this Mac produced these accepted results:

- `um hello Alice can you send it today` became `Hello Alice, can you send it today?`.
- `um I have 12 tickets not 13 please keep them` became `I have 12 tickets, not 13. Please keep them.`.
- `uh please bring apples oranges and pears` became `Please bring apples, oranges, and pears.`.

Selected model cases also exercised protected quotes, URLs, command flags, negative quantities, paragraph breaks, and dictated instructions. Some results were rejected and fell back to Balanced cleanup. A fallback is a passing preservation check, not a successful AI formatting result. Generative output can vary with system model updates, so the `--model` check validates retained words and protected literals rather than promising identical punctuation on every run.

These are synthetic text cases, not a speech-recognition accuracy evaluation. They do not establish word error rates, performance improvements, or a physical microphone-to-editor session.

Sentence rollback uses the system NaturalLanguage sentence tokenizer instead of treating every period as a boundary. Regression cases cover URLs and paths at the end of a sentence, dotted abbreviations, and proper names after abbreviations. Ambiguous two-word `never mind` wording is preserved unless a restart cue is present.
