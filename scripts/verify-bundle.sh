#!/bin/bash
set -euo pipefail
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
app="${1:-$project_dir/release/Voco.app}"
binary="$app/Contents/MacOS/Voco"
[[ -x "$binary" ]] || { echo 'Missing Rust executable.' >&2; exit 1; }
codesign --verify --deep --strict "$app"
"$binary" --version
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app/Contents/Info.plist")" == org.vocoapp.Voco ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print :LSUIElement' "$app/Contents/Info.plist")" == true ]]
if find "$app/Contents" \( -name '*Electron*' -o -name '*.asar' -o -name '*.swift' -o -name '*.js' -o -name '*.html' -o -name 'VocoNative*' \) -print | grep -q .; then
    echo 'The bundle contains files from the previous application runtime.' >&2
    exit 1
fi
if otool -L "$binary" | tail -n +2 | awk '{print $1}' | grep -Ev '^(/System/Library/|/usr/lib/)'; then
    echo 'The executable has a non-system dynamic dependency.' >&2
    exit 1
fi
build_binary="$project_dir/target/release/voco"
if [[ -f "$build_binary" ]]; then
    built_uuid="$(xcrun dwarfdump --uuid "$build_binary" | awk '{print $2}')"
    app_uuid="$(xcrun dwarfdump --uuid "$binary" | awk '{print $2}')"
    [[ -n "$app_uuid" && "$app_uuid" == "$built_uuid" ]] || { echo 'The app differs from the current release executable.' >&2; exit 1; }
fi
printf 'Verified native app bundle: %s\n' "$app"
