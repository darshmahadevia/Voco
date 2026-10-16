#!/bin/bash
set -euo pipefail
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
cd "$project_dir"
: "${VOCO_VERIFY_AUDIO:?Set VOCO_VERIFY_AUDIO to a mono 16 kHz WAV.}"
: "${VOCO_VERIFY_EXPECTED_TRANSCRIPT:?Set the expected spoken words.}"
cargo build --locked
normalize() { LC_ALL=C tr -cs '[:alnum:]' ' ' | awk '{$1=$1; print tolower($0)}'; }
expected="$(printf '%s' "$VOCO_VERIFY_EXPECTED_TRANSCRIPT" | normalize)"
[[ -n "$expected" ]] || { echo 'Expected transcript has no words.' >&2; exit 1; }
for model in moonshine parakeet whisper; do
    transcript="$(target/debug/voco --transcribe "$model" "$VOCO_VERIFY_AUDIO")"
    actual="$(printf '%s' "$transcript" | normalize)"
    if [[ "$actual" != "$expected" ]]; then
        printf '%s transcript differed.\nExpected: %s\nActual: %s\n' "$model" "$expected" "$actual" >&2
        exit 1
    fi
    printf 'PASS %s: %s\n' "$model" "$transcript"
done
