#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRATCH="$(mktemp -d "${TMPDIR:-/tmp}/voco-deferred.XXXXXX")"
trap 'rm -rf "$SCRATCH"' EXIT
cd "$ROOT"
xcrun swiftc -swift-version 6 -target arm64-apple-macos26.0 -emit-library -static -emit-module -module-name VocoCore \
  Sources/VocoCore/*.swift -o "$SCRATCH/libVocoCore.a" -emit-module-path "$SCRATCH/VocoCore.swiftmodule"
cat native/Sources/SessionTypes.swift native/Sources/TranscriptLedger.swift native/Sources/UsageStats.swift \
  native/Sources/AudioMeter.swift native/Sources/TranscriptPolisher.swift native/Sources/NativeProtocol.swift native/Sources/TextInsertion.swift \
  native/Sources/NativeCoordinator.swift native/Tests/InsertionCheck.swift > "$SCRATCH/check.swift"
python3 - "$SCRATCH/check.swift" "$ROOT/native/Tests/DeferredDictationCheck.swift" <<'PY'
import sys
path, fixture = sys.argv[1:]
source = open(path).read()
source = source[:source.index('@main', source.index('@MainActor enum InsertionFixture'))]
source = source.replace('import ApplicationServices', '@preconcurrency import ApplicationServices').replace('@preconcurrency @preconcurrency', '@preconcurrency')
open(path, 'w').write(source + '\n' + open(fixture).read())
PY
xcrun swiftc -swift-version 6 -parse-as-library -target arm64-apple-macos26.0 \
  -I "$SCRATCH" -L "$SCRATCH" -lVocoCore "$SCRATCH/check.swift" -o "$SCRATCH/check"
VOCO_SKIP_PREFERENCE_MIGRATION=1 VOCO_PREFERENCE_SUITE="Voco-deferred-check-$$" "$SCRATCH/check"
cat native/Sources/ShortcutMonitor.swift native/Tests/ShortcutMonitorCheck.swift > "$SCRATCH/shortcut.swift"
xcrun swiftc -swift-version 6 -parse-as-library -target arm64-apple-macos26.0 \
  -I "$SCRATCH" -L "$SCRATCH" -lVocoCore "$SCRATCH/shortcut.swift" -o "$SCRATCH/shortcut"
"$SCRATCH/shortcut"
