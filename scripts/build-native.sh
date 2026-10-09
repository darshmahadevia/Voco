#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NATIVE="$ROOT/native"
BUILD="${VOCO_NATIVE_BUILD_DIR:-$HOME/Library/Caches/Voco/Native}"
if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "build-native.sh requires macOS." >&2
  exit 1
fi
if [[ "$(uname -m)" != "arm64" ]]; then
  echo "Voco's first native build targets Apple Silicon (arm64)." >&2
  exit 1
fi

# Keep signed bundles outside synced folders, which can reattach Finder metadata.
if [[ ! -e "$BUILD" && -d "$NATIVE/build" && ! -L "$NATIVE/build" ]]; then
  mkdir -p "$(dirname "$BUILD")"
  mv "$NATIVE/build" "$BUILD"
fi
mkdir -p "$BUILD"
BUILD="$(cd "$BUILD" && pwd -P)"
if [[ -L "$NATIVE/build" || ! -e "$NATIVE/build" ]]; then
  ln -sfn "$BUILD" "$NATIVE/build"
elif [[ ! "$NATIVE/build" -ef "$BUILD" ]]; then
  echo "native/build is a directory outside the configured build cache: $BUILD" >&2
  exit 1
fi
DEPENDENCIES="$BUILD/dependencies"
MOONSHINE="$DEPENDENCIES/moonshine"
APP="$BUILD/VocoNative.app"
EXECUTABLE="$APP/Contents/MacOS/VocoNative"
ARCHIVE="$DEPENDENCIES/moonshine-voice-macos-arm64.tar.gz"
ARCHIVE_URL="https://github.com/moonshine-ai/moonshine/releases/download/v0.1.5/moonshine-voice-macos-arm64.tar.gz"
ARCHIVE_SHA256="51151f98eb1b20b8fc141bab361a1574dbfdbef8300b632ee6679e373112e0f6"

mkdir -p "$DEPENDENCIES"
if [[ ! -f "$ARCHIVE" ]]; then
  TEMP_ARCHIVE="$ARCHIVE.part"
  rm -f "$TEMP_ARCHIVE"
  curl --fail --location --retry 3 --output "$TEMP_ARCHIVE" "$ARCHIVE_URL"
  mv "$TEMP_ARCHIVE" "$ARCHIVE"
fi
ACTUAL_SHA256="$(shasum -a 256 "$ARCHIVE" | awk '{print $1}')"
if [[ "$ACTUAL_SHA256" != "$ARCHIVE_SHA256" ]]; then
  echo "Moonshine archive checksum mismatch: $ACTUAL_SHA256" >&2
  exit 1
fi

if [[ ! -f "$MOONSHINE/lib/libmoonshine.a" || ! -f "$MOONSHINE/include/moonshine-c-api.h" ]]; then
  rm -rf "$MOONSHINE"
  mkdir -p "$MOONSHINE"
  tar -xzf "$ARCHIVE" -C "$MOONSHINE" --strip-components=1
fi

MODULE="$MOONSHINE/include/module.modulemap"
cp "$NATIVE/Moonshine/module.modulemap" "$MODULE"
CORE_MODULE="$BUILD/VocoCore.swiftmodule"
CORE_LIBRARY="$BUILD/libVocoCore.a"
mkdir -p "$BUILD"
rm -rf "$APP"

MACOSX_DEPLOYMENT_TARGET=13.0 swiftc \
  -swift-version 6 \
  -target arm64-apple-macos13.0 \
  -parse-as-library \
  -module-name VocoCore \
  -emit-module \
  -emit-module-path "$CORE_MODULE" \
  -emit-library \
  -static \
  -o "$CORE_LIBRARY" \
  "$ROOT"/Sources/VocoCore/*.swift

mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$NATIVE/Info.plist" "$APP/Contents/Info.plist"
VERSION="$(node -p 'require(process.argv[1]).version' "$ROOT/package.json")"
plutil -replace CFBundleShortVersionString -string "$VERSION" "$APP/Contents/Info.plist"
plutil -replace CFBundleVersion -string "$VERSION" "$APP/Contents/Info.plist"
cp "$ROOT/Resources/Voco.icns" "$APP/Contents/Resources/Voco.icns"
printf 'APPL????' > "$APP/Contents/PkgInfo"

MACOSX_DEPLOYMENT_TARGET=26.0 swiftc \
  -swift-version 6 \
  -target arm64-apple-macos26.0 \
  -O \
  -I "$BUILD" \
  -I "$MOONSHINE/include" \
  -L "$MOONSHINE/lib" \
  -lmoonshine \
  -Xlinker -force_load -Xlinker "$CORE_LIBRARY" \
  -framework AppKit \
  -framework AVFoundation \
  -framework ApplicationServices \
  -framework Accelerate \
  -framework CoreML \
  -framework Foundation \
  -framework Security \
  -framework SystemConfiguration \
  -framework Network \
  -lc++ \
  -lz \
  -lsqlite3 \
  -o "$EXECUTABLE" \
  "$ROOT"/Sources/Voco/ShortcutMonitor.swift \
  "$ROOT"/Sources/Voco/TextInsertion.swift \
  "$ROOT"/Sources/Voco/LiveTextWriter.swift \
  "$NATIVE"/Sources/*.swift

chmod 755 "$EXECUTABLE"
xattr -cr "$APP"
xattr -d com.apple.FinderInfo "$APP" 2>/dev/null || true
SIGNING_IDENTITY="${VOCO_CODESIGN_IDENTITY:-}"
SIGNING_CONFIG="$HOME/Library/Application Support/Voco/signing-identity"
if [[ -z "$SIGNING_IDENTITY" && -f "$SIGNING_CONFIG" ]]; then
  SIGNING_IDENTITY="$(cat "$SIGNING_CONFIG")"
fi
SIGNING_IDENTITY="${SIGNING_IDENTITY:--}"
codesign --force --deep --sign "$SIGNING_IDENTITY" --identifier org.vocoapp.Voco.Native "$APP"
xattr -d com.apple.FinderInfo "$APP" 2>/dev/null || true
codesign --verify --deep --strict "$APP"
plutil -lint "$APP/Contents/Info.plist" >/dev/null
echo "Built $APP"
