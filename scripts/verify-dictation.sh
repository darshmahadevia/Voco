#!/bin/bash
set -euo pipefail
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
scratch="$(mktemp -d "${TMPDIR:-/tmp}/voco-dictation.XXXXXX")"
trap 'rm -rf "$scratch"' EXIT
phrase='The quick brown fox jumps over the lazy dog. This is a local speech recognition test.'
say -v Samantha -o "$scratch/phrase.aiff" "$phrase"
swiftc -swift-version 6 -parse-as-library "$project_dir/native/Tests/LiveDictationCheck.swift" -o "$scratch/check"
env -u ELECTRON_RUN_AS_NODE open -g "$HOME/Applications/Voco.app"
printf 'Keep the disposable editor focused. Speech plays through your speakers into the microphone.\n'
"$scratch/check" "$scratch/phrase.aiff" "$phrase"
