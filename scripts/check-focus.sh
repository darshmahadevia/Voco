#!/bin/bash
set -euo pipefail
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
scratch_dir="$(mktemp -d "${TMPDIR:-/tmp}/voco-focus.XXXXXX")"
trap 'rm -rf "$scratch_dir"' EXIT
cd "$project_dir"
if test "$#" -eq 0; then
    cat Sources/Voco/TextInsertion.swift Tests/VocoLifecycleChecks/FocusCheck.swift > "$scratch_dir/FocusCheck.swift"
else
    git show "$1:Sources/Voco/TextInsertion.swift" > "$scratch_dir/FocusCheck.swift"
    awk '/^@main struct FocusCheck/ { exit } { print }' Tests/VocoLifecycleChecks/FocusCheck.swift >> "$scratch_dir/FocusCheck.swift"
    cat Tests/VocoLifecycleChecks/BaselineFocusCheck.swift >> "$scratch_dir/FocusCheck.swift"
fi
xcrun swiftc -swift-version 6 -parse-as-library -target "$(uname -m)-apple-macosx26.0" \
    "$scratch_dir/FocusCheck.swift" -o "$scratch_dir/check"
"$scratch_dir/check"
