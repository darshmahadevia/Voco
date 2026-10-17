# Verify transcript cleanup

Run the cleanup tests from the repository root:

```sh
cargo test --locked cleanup::tests
```

The tests exercise the Rust cleanup code in `src/cleanup.rs`. Fixtures in `Tests/fixtures` cover expected Balanced output, protected literals, rejected edits, and repeated cleanup. The same fixtures check that Fast preserves the original text and Accurate keeps Balanced output when a supplied generator reports unavailability. Additional tests verify accepted formatting, rejected changes, generation failures, and inputs that must skip the model. These deterministic tests do not require Apple Intelligence.

To try a sentence through the executable:

```sh
cargo run -- --cleanup balanced 'Um, send it today.'
```

The result is `Send it today.`. See [output modes](local-dictation.md) for behavior and limitations.

These checks use text fixtures. They do not measure speech recognition accuracy, live microphone capture, or dictation latency. The [earlier Swift cleanup record](migration/pre-rust-cleanup-verification.md) preserves the retired implementation's results.

## Verify Apple FoundationModels

With Apple Intelligence enabled and its model ready, run:

```sh
cargo test --locked cleanup::tests::foundation_models_formats_on_device -- --ignored --nocapture
cargo run -- --cleanup accurate 'um hello Alice can you send it today'
```

The on-device test requires an accepted formatting change without a fallback notice. It fails if the model is unavailable, times out, or produces an unsafe result. On this Mac, the restored bridge produced `Hello Alice, can you send it today?`. Model punctuation can vary with system updates.

The app statically links `native/FoundationFormatting.swift` into the Rust executable. Formatting uses the original prompt and structured response, runs on the inference worker, and falls back after eight seconds. The Rust validator rejects changed words, protected literals, quantities, symbols, and line breaks. Inputs over 2,000 UTF-8 bytes keep Balanced output without calling the model.
