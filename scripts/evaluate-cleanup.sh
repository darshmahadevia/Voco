#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRATCH="$(mktemp -d "${TMPDIR:-/tmp}/voco-cleanup-evaluation.XXXXXX")"
trap 'rm -rf "$SCRATCH"' EXIT
xcrun swiftc -swift-version 6 -parse-as-library -target "$(uname -m)-apple-macosx26.0" \
  "$ROOT/native/Sources/TranscriptPolisher.swift" "$ROOT/native/Tests/CleanupEvaluation.swift" -o "$SCRATCH/evaluate"
"$SCRATCH/evaluate" "$ROOT/native/Tests/Fixtures/cleanup-cases.json" "$@"
