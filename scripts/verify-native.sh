#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="$ROOT/native/build/VocoNative.app"
EXECUTABLE="$APP/Contents/MacOS/VocoNative"
MODEL_DIRECTORY="${VOCO_MODEL_DIRECTORY:-}"
TRANSCRIBE_FIXTURE="${VOCO_TRANSCRIBE_FIXTURE:-}"

"$ROOT/scripts/check-transcript-polisher.sh"
"$ROOT/scripts/build-native.sh"
swiftc \
  -swift-version 6 \
  -target arm64-apple-macos26.0 \
  -o "$ROOT/native/build/session-ledger-smoke" \
  "$ROOT/native/Sources/SessionTypes.swift" \
  "$ROOT/native/Sources/TranscriptLedger.swift" \
  "$ROOT/native/Tests/SessionLedgerSmoke.swift"
"$ROOT/native/build/session-ledger-smoke"
node "$ROOT/native/Tests/verify-protocol.mjs" "$EXECUTABLE"

if [[ -n "$MODEL_DIRECTORY" ]]; then
  "$EXECUTABLE" --model-status --model-directory "$MODEL_DIRECTORY"
fi

if [[ -n "$TRANSCRIBE_FIXTURE" ]]; then
  if [[ -z "$MODEL_DIRECTORY" ]]; then
    echo "Set VOCO_MODEL_DIRECTORY when providing VOCO_TRANSCRIBE_FIXTURE." >&2
    exit 2
  fi
  "$EXECUTABLE" --transcribe-file "$TRANSCRIBE_FIXTURE" --model-directory "$MODEL_DIRECTORY"
fi

xattr -d com.apple.FinderInfo "$APP" 2>/dev/null || true
codesign --verify --deep --strict "$APP"
