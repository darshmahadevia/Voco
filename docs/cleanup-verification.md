# Verify transcript cleanup

Run the cleanup tests from the repository root:

```sh
cargo test --locked cleanup::tests
```

The tests exercise the Rust cleanup code in `src/cleanup.rs`. Fixtures in `Tests/fixtures` cover expected Balanced output, protected literals, rejected edits, and repeated cleanup. The same fixtures check that Fast preserves the original text and Accurate returns Balanced output with an unavailable-FoundationModels notice for nonempty results.

To try a sentence through the executable:

```sh
cargo run -- --cleanup balanced 'Um, send it today.'
```

The result is `Send it today.`. See [output modes](local-dictation.md) for behavior and limitations.

These checks use text fixtures. They do not measure speech recognition accuracy, live microphone capture, or dictation latency. The [earlier Swift cleanup record](migration/pre-rust-cleanup-verification.md) preserves the retired implementation's results.
