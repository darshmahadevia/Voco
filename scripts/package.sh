#!/bin/bash
set -euo pipefail
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
cd "$project_dir"
[[ "$(uname -s)" == Darwin && "$(uname -m)" == arm64 ]] || { echo 'Voco requires an Apple Silicon Mac.' >&2; exit 1; }
cargo build --release --locked
bundle_root="$HOME/Library/Caches/Voco/Rust"
mkdir -p "$bundle_root"
staging="$(mktemp -d "$bundle_root/package.XXXXXX")"
trap 'rm -rf "$staging"' EXIT
app="$staging/Voco.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp target/release/voco "$app/Contents/MacOS/Voco"
cp Resources/Info.plist "$app/Contents/Info.plist"
version="$(cargo metadata --no-deps --format-version 1 | /usr/bin/plutil -extract packages.0.version raw -o - -)"
/usr/bin/plutil -replace CFBundleShortVersionString -string "$version" "$app/Contents/Info.plist"
/usr/bin/plutil -replace CFBundleVersion -string "$version" "$app/Contents/Info.plist"
cp Resources/Voco.icns "$app/Contents/Resources/"
mkdir -p "$app/Contents/Resources/Fonts"
cp Resources/Fonts/Manrope-Regular.ttf "$app/Contents/Resources/Fonts/Manrope-Regular.ttf"
cp -R Resources/licenses "$app/Contents/Resources/"
cp Resources/Fonts/OFL.txt "$app/Contents/Resources/licenses/Manrope-OFL.txt"
identity="${VOCO_CODESIGN_IDENTITY:-}"
if [[ -z "$identity" && -f "$HOME/Library/Application Support/Voco/signing-identity" ]]; then
    identity="$(cat "$HOME/Library/Application Support/Voco/signing-identity")"
fi
xattr -cr "$app"
codesign --force --options runtime --timestamp=none --entitlements Resources/entitlements.mac.plist --sign "${identity:--}" "$app"
codesign --verify --deep --strict "$app"
if [[ -e "$bundle_root/Voco.app" || -L "$bundle_root/Voco.app" ]]; then
    rm -rf "$bundle_root/Voco.app"
fi
mv "$app" "$bundle_root/Voco.app"
if [[ -e release && ! -L release ]]; then
    echo 'release exists and is not a symlink. Move it aside and rerun packaging.' >&2
    exit 1
fi
ln -sfn "$bundle_root" release
if [[ "${1:-}" == dmg ]]; then
    hdiutil create -volname Voco -srcfolder "$bundle_root/Voco.app" -ov -format UDZO "$bundle_root/Voco.dmg"
fi
./scripts/verify-bundle.sh "$bundle_root/Voco.app"
printf 'Built %s\n' "$bundle_root/Voco.app"
