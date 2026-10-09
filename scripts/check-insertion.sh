#!/bin/bash
set -euo pipefail
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
scratch_dir="$(mktemp -d "${TMPDIR:-/tmp}/voco-insertion-check.XXXXXX")"
trap 'rm -rf "$scratch_dir"' EXIT
cd "$project_dir"
xcrun swiftc -swift-version 6 -target "$(uname -m)-apple-macosx26.0" \
    -emit-library -static -emit-module -module-name VocoCore \
    Sources/VocoCore/*.swift -o "$scratch_dir/libVocoCore.a" \
    -emit-module-path "$scratch_dir/VocoCore.swiftmodule"
cat Sources/Voco/AppModel.swift Sources/Voco/TextInsertion.swift Sources/Voco/LiveTextWriter.swift \
    > "$scratch_dir/InsertionCheck.swift"
awk '/^@MainActor/ { exit } { print }' Sources/Voco/ShortcutMonitor.swift >> "$scratch_dir/InsertionCheck.swift"
cat Tests/VocoLifecycleChecks/InsertionCheck.swift >> "$scratch_dir/InsertionCheck.swift"
xcrun swiftc -swift-version 6 -parse-as-library -target "$(uname -m)-apple-macosx26.0" \
    -I "$scratch_dir" -L "$scratch_dir" -lVocoCore \
    Sources/Voco/SpeechSession.swift "$scratch_dir/InsertionCheck.swift" -o "$scratch_dir/check"
"$scratch_dir/check"
