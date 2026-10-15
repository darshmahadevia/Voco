#!/bin/bash
set -euo pipefail
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
app_dir="$HOME/Applications/Voco.app"
bundle_dir="$project_dir/release/mac-arm64/Voco.app"
launch_services="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
cd "$project_dir"
if test "${1:-}" != --built; then
    npm run pack
fi
node scripts/verify-installed-version.cjs "$bundle_dir"
codesign --verify --deep --strict "$bundle_dir"
if test "$bundle_dir" -ef "$app_dir"; then
    printf 'Already installed %s\n' "$app_dir"
    exit 0
fi
if test -e "$app_dir"; then
    existing_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app_dir/Contents/Info.plist")"
    if test "$existing_id" != org.vocoapp.Voco; then
        printf 'Another app exists at %s; it was left unchanged.\n' "$app_dir" >&2
        exit 1
    fi
    while IFS= read -r voco_pid; do
        running_binary="$(ps -p "$voco_pid" -o comm= || true)"
        if test "$running_binary" = "$app_dir/Contents/MacOS/Voco"; then
            kill -TERM "$voco_pid"
        fi
    done < <(pgrep -x Voco || true)
    "$launch_services" -u "$app_dir" || true
    mkdir -p "$HOME/.Trash"
    previous_app="$(mktemp -d "$HOME/.Trash/Voco-previous.XXXXXX")"
    mv "$app_dir" "$previous_app/Voco.app"
fi
mkdir -p "$HOME/Applications"
"$launch_services" -u "$bundle_dir" || true
mv "$bundle_dir" "$app_dir"
ln -s "$app_dir" "$bundle_dir"
"$launch_services" -f "$app_dir"
node scripts/verify-installed-version.cjs
codesign --verify --deep --strict "$app_dir"
printf 'Installed %s\n' "$app_dir"
