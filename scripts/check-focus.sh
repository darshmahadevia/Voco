#!/bin/bash
set -euo pipefail
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
scratch_dir="$(mktemp -d "${TMPDIR:-/tmp}/voco-focus.XXXXXX")"
trap 'rm -rf "$scratch_dir"' EXIT
cd "$project_dir"
cat native/Sources/TextInsertion.swift native/Tests/FocusCheck.swift > "$scratch_dir/FocusCheck.swift"
xcrun swiftc -swift-version 6 -parse-as-library -target "$(uname -m)-apple-macosx26.0" \
    "$scratch_dir/FocusCheck.swift" -o "$scratch_dir/check"
"$scratch_dir/check"
