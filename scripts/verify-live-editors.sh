#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD="$ROOT/native/build"
HELPER="$BUILD/VocoNative.app"
if [[ ! -x "$HELPER/Contents/MacOS/VocoNative" ]]; then
  echo "Build Voco and enable VocoNative in macOS Accessibility settings first." >&2
  exit 2
fi
if [[ -n "${VOCO_VERIFY_AUDIO_FIXTURE:-}" ]]; then
  : "${VOCO_VERIFY_MODEL_DIRECTORY:?Set the cached model directory.}"
  : "${VOCO_VERIFY_EXPECTED_TRANSCRIPT:?Set the literal expected fixture transcript.}"
fi
# Build only editor fixtures; preserve the helper signature and its permission grant.
swiftc -swift-version 6 -parse-as-library "$ROOT/native/Tests/native-editor.swift" -o "$BUILD/native-editor-check"
swiftc -swift-version 6 -parse-as-library "$ROOT/native/Tests/web-editor.swift" -o "$BUILD/web-editor-check"
"$BUILD/native-editor-check" "$HELPER"
"$BUILD/web-editor-check" "$HELPER" "$ROOT/native/Tests/editors.html"
node "$ROOT/scripts/verify-electron-insertion.mjs"
