#!/bin/bash
set -euo pipefail
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
cd "$project_dir"
swift_compiler="$(xcrun --find swiftc)"
testing_plugin="$(dirname "$swift_compiler")/../lib/swift/host/plugins/testing/libTestingMacros.dylib"
test_flags=()
if test -f "$testing_plugin"; then
    test_flags=(-Xswiftc -load-plugin-library -Xswiftc "$testing_plugin")
fi
swift test --disable-xctest --scratch-path "${VOCO_BUILD_DIR:-$HOME/Library/Caches/Voco/Build}" "${test_flags[@]}"
