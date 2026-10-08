#!/bin/bash
set -euo pipefail
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
scratch_dir="$(mktemp -d "${TMPDIR:-/tmp}/voco-permissions.XXXXXX")"
trap 'rm -rf "$scratch_dir"' EXIT
cd "$project_dir"
xcrun swiftc -swift-version 6 -target "$(uname -m)-apple-macosx26.0" \
    -emit-library -static -emit-module -module-name VocoCore \
    Sources/VocoCore/*.swift -o "$scratch_dir/libVocoCore.a" \
    -emit-module-path "$scratch_dir/VocoCore.swiftmodule"
if test "$#" -eq 0; then
    cat Sources/Voco/AppModel.swift > "$scratch_dir/AppModelCheck.swift"
    check=Tests/VocoLifecycleChecks/PermissionCheck.swift
else
    git show "$1:Sources/Voco/AppModel.swift" > "$scratch_dir/AppModelCheck.swift"
    check=Tests/VocoLifecycleChecks/BaselinePermissionCheck.swift
fi
awk '/^@MainActor/ { exit } { print }' Sources/Voco/ShortcutMonitor.swift >> "$scratch_dir/AppModelCheck.swift"
cat Tests/VocoLifecycleChecks/PermissionFixture.swift "$check" >> "$scratch_dir/AppModelCheck.swift"
xcrun swiftc -swift-version 6 -parse-as-library -target "$(uname -m)-apple-macosx26.0" \
    -I "$scratch_dir" -L "$scratch_dir" -lVocoCore \
    Sources/Voco/SpeechSession.swift Sources/Voco/TextInsertion.swift Sources/Voco/LiveTextWriter.swift \
    "$scratch_dir/AppModelCheck.swift" -o "$scratch_dir/check"
"$scratch_dir/check"
