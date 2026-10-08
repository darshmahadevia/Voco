#!/bin/bash
set -euo pipefail
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
scratch_dir="$(mktemp -d "${TMPDIR:-/tmp}/voco-recovery.XXXXXX")"
trap 'rm -rf "$scratch_dir"' EXIT
cd "$project_dir"

xcrun swiftc -swift-version 6 -target "$(uname -m)-apple-macosx26.0" \
    -emit-library -static -emit-module -module-name VocoCore \
    Sources/VocoCore/*.swift -o "$scratch_dir/libVocoCore.a" \
    -emit-module-path "$scratch_dir/VocoCore.swiftmodule"
cat Sources/Voco/AppModel.swift Tests/VocoLifecycleChecks/RecoveryCheck.swift > "$scratch_dir/AppModelCheck.swift"
sources=()
for source in Sources/Voco/*.swift; do
    case "$source" in
        Sources/Voco/AppModel.swift|Sources/Voco/VocoApp.swift) continue ;;
    esac
    sources+=("$source")
done
xcrun swiftc -swift-version 6 -parse-as-library -target "$(uname -m)-apple-macosx26.0" \
    -I "$scratch_dir" -L "$scratch_dir" -lVocoCore \
    "${sources[@]}" "$scratch_dir/AppModelCheck.swift" -o "$scratch_dir/check"
"$scratch_dir/check"
