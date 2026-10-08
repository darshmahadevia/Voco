#!/bin/bash
set -euo pipefail
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
app_dir="$HOME/Applications/Voco.app"
bundle_dir="${VOCO_BUILD_DIR:-$HOME/Library/Caches/Voco/Build}/Bundle/Voco.app"
previous_hash=""
cd "$project_dir"

if test -e "$app_dir"; then
    existing_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app_dir/Contents/Info.plist" 2>/dev/null || true)"
    if test "$existing_id" != org.utterapp.Utter; then
        printf 'Another app already exists at %s; it was left unchanged.\n' "$app_dir" >&2
        exit 1
    fi
    previous_hash="$(codesign -dv --verbose=4 "$app_dir" 2>&1 | sed -n 's/^CDHash=//p')"
fi
./scripts/build.sh
next_hash="$(codesign -dv --verbose=4 "$bundle_dir" 2>&1 | sed -n 's/^CDHash=//p')"
signature_changed=false
if test -n "$previous_hash" && test "$previous_hash" != "$next_hash"; then
    signature_changed=true
    while IFS= read -r voco_pid; do
        running_binary="$(ps -p "$voco_pid" -o comm= || true)"
        if test "$running_binary" = "$app_dir/Contents/MacOS/Voco"; then
            kill -TERM "$voco_pid"
        fi
    done < <(pgrep -x Voco || true)
fi
mkdir -p "$HOME/Applications"
ditto --noextattr "$bundle_dir" "$app_dir"
xattr -cr "$app_dir"
codesign --verify --deep --strict "$app_dir"
if test "$signature_changed" = true || test -z "$previous_hash"; then
    # A stale Input Monitoring record can deny the event tap even with Accessibility granted.
    if ! tccutil reset ListenEvent org.utterapp.Utter; then
        printf 'Could not clear the old Input Monitoring record. If shortcuts remain unavailable, remove the old app entry in Input Monitoring.\n' >&2
    fi
fi
if test "$signature_changed" = true; then
    if tccutil reset Accessibility org.utterapp.Utter; then
        printf 'Development signature changed. Enable Keyboard access again in macOS settings.\n'
    else
        printf 'Remove Voco from the keyboard permission list and add the installed app again.\n' >&2
    fi
fi
printf 'Installed %s\n' "$app_dir"
