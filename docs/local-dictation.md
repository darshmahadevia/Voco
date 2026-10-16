# Local dictation output

The speech model and output mode are separate choices. Moonshine, Parakeet, and Whisper recognize English speech locally. The output mode controls cleanup after recognition and before insertion.

Fast preserves the speech model's transcript.

Balanced removes hesitation fillers and spoken restarts with Rust token and source-range rules. It preserves quotes, code, links, email addresses, paths, quantities, and line endings. For example, `Um, send it today.` becomes `Send it today.` The migration retains the existing cleanup examples as executable fixtures under `Tests/fixtures`.

Accurate currently uses Balanced cleanup and displays a notice. Apple's FoundationModels formatting is unavailable in this Rust build. There is no cloud fallback or hidden model download.

The Rust sentence and part-of-speech rules are conservative heuristics. They pass the migrated fixtures, but unfamiliar wording and abbreviations can differ from the previous Apple NaturalLanguage implementation. Review the output before sending it. Fast bypasses these cleanup rules.

Raw audio and transcripts stay in memory. Turning off transcript retention clears recent text and the retained raw transcript. If text cannot be inserted, recovery keeps the complete result available to copy.
