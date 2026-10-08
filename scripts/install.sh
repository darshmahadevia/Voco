#!/bin/bash
set -euo pipefail
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
app_dir="$HOME/Applications/Voco.app"
bundle_dir="${VOCO_BUILD_DIR:-$HOME/Library/Caches/Voco/Build}/Bundle/Voco.app"
previous_hash=""
previous_requirement=""
existing_id=""
bundle_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$project_dir/Resources/Info.plist")"
cd "$project_dir"

if test -e "$app_dir"; then
    existing_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app_dir/Contents/Info.plist" 2>/dev/null || true)"
    existing_binary="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$app_dir/Contents/Info.plist" 2>/dev/null || true)"
    if test "$existing_binary" != Voco || { test "$existing_id" != "$bundle_id" && test "$existing_id" != org.utterapp.Utter; }; then
        printf 'Another app already exists at %s; it was left unchanged.\n' "$app_dir" >&2
        exit 1
    fi
    previous_hash="$(codesign -dv --verbose=4 "$app_dir" 2>&1 | sed -n 's/^CDHash=//p')"
    previous_requirement="$(codesign -d -r- "$app_dir" 2>&1 | sed -n 's/^.*designated => //p')"
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
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$app_dir"
next_requirement="$(codesign -d -r- "$app_dir" 2>&1 | sed -n 's/^.*designated => //p')"
if test "$existing_id" != "$bundle_id" || test "$previous_requirement" != "$next_requirement"; then
    # macOS grants are tied to the designated requirement, not just the bundle identifier.
    if ! tccutil reset ListenEvent "$bundle_id"; then
        printf 'Could not clear Voco Input Monitoring access. Remove its old entry if shortcuts remain unavailable.\n' >&2
    fi
    if ! tccutil reset Microphone "$bundle_id"; then
        printf 'Could not clear Voco microphone access. Enable it in microphone settings if preparation fails.\n' >&2
    fi
    if tccutil reset Accessibility "$bundle_id"; then
        printf 'Enable Keyboard access in macOS settings and prepare English speech to grant microphone access.\n'
    else
        printf 'Remove Voco from the keyboard permission list and add the installed app again.\n' >&2
    fi
fi
if test "$existing_id" = org.utterapp.Utter; then
    printf 'Voco now has its own permission identity. Enable the new Voco entry; Utter permissions were left unchanged.\n'
fi
printf 'Installed %s\n' "$app_dir"
