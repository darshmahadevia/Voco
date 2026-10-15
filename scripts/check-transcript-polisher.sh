#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRATCH="$(mktemp -d "${TMPDIR:-/tmp}/voco-polisher.XXXXXX")"
trap 'rm -rf "$SCRATCH"' EXIT
xcrun swiftc -swift-version 6 -parse-as-library -target "$(uname -m)-apple-macosx26.0" \
  "$ROOT/native/Sources/TranscriptPolisher.swift" "$ROOT/native/Tests/TranscriptPolisherCheck.swift" -o "$SCRATCH/check"
"$SCRATCH/check" "$@"
