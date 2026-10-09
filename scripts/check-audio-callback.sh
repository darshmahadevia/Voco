#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD="$ROOT/native/build"
MOONSHINE="$BUILD/dependencies/moonshine"

if [[ ! -f "$MOONSHINE/lib/libmoonshine.a" || ! -f "$MOONSHINE/include/module.modulemap" ]]; then
  "$ROOT/scripts/build-native.sh"
fi

swiftc \
  -swift-version 6 \
  -target arm64-apple-macos26.0 \
  -O \
  -parse-as-library \
  -I "$MOONSHINE/include" \
  -L "$MOONSHINE/lib" \
  -lmoonshine \
  -framework AppKit \
  -framework AVFoundation \
  -framework ApplicationServices \
  -framework Accelerate \
  -framework CoreML \
  -framework Foundation \
  -framework Security \
  -framework SystemConfiguration \
  -framework Network \
  -lc++ \
  -lz \
  -lsqlite3 \
  -o "$BUILD/audio-tap-isolation-smoke" \
  "$ROOT/native/Sources/TranscriptLedger.swift" \
  "$ROOT/native/Sources/SessionTypes.swift" \
  "$ROOT/native/Sources/NativeProtocol.swift" \
  "$ROOT/native/Sources/MoonshineEngine.swift" \
  "$ROOT/native/Tests/AudioTapIsolationSmoke.swift"

"$BUILD/audio-tap-isolation-smoke"
