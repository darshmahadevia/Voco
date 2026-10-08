#!/bin/bash
set -euo pipefail

project_dir="$(cd "$(dirname "$0")/.." && pwd)"
cache_dir="${VOCO_BUILD_DIR:-$HOME/Library/Caches/Voco/Build}"
bundle_dir="$cache_dir/Bundle/Voco.app"
cd "$project_dir"

swift build --scratch-path "$cache_dir" -c release --product Voco
binary_dir="$(swift build --scratch-path "$cache_dir" -c release --show-bin-path)"
mkdir -p "$bundle_dir/Contents/MacOS" "$bundle_dir/Contents/Resources" "$project_dir/build"
cp "$binary_dir/Voco" "$bundle_dir/Contents/MacOS/Voco"
cp Resources/Info.plist "$bundle_dir/Contents/Info.plist"
xattr -cr "$bundle_dir"
bundle_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' Resources/Info.plist)"
codesign --force --sign "${VOCO_SIGNING_IDENTITY:--}" --identifier "$bundle_id" "$bundle_dir"
codesign --verify --deep --strict "$bundle_dir"
if test -e "$project_dir/build/Voco.app" || test -L "$project_dir/build/Voco.app"; then
    rm -rf "$project_dir/build/Voco.app"
fi
ln -s "$bundle_dir" "$project_dir/build/Voco.app"
printf 'Built %s/build/Voco.app\n' "$project_dir"
