#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="${VOCO_NATIVE_BUILD_DIR:-$HOME/Library/Caches/Voco/Native}"
[[ "$(uname -s)" == Darwin && "$(uname -m)" == arm64 ]] || { echo 'Voco requires an Apple Silicon Mac.' >&2; exit 1; }
mkdir -p "$BUILD"
BUILD="$(cd "$BUILD" && pwd -P)"
if [[ -L "$ROOT/native/build" || ! -e "$ROOT/native/build" ]]; then
  ln -sfn "$BUILD" "$ROOT/native/build"
elif [[ ! "$ROOT/native/build" -ef "$BUILD" ]]; then
  echo 'native/build must point to the configured native cache.' >&2
  exit 1
fi
DEPS="$BUILD/dependencies"
mkdir -p "$DEPS"
ARCHIVE="$DEPS/moonshine-voice-macos-arm64.tar.gz"
if [[ ! -f "$ARCHIVE" ]]; then
  curl --fail --location --retry 3 -o "$ARCHIVE.part" https://github.com/moonshine-ai/moonshine/releases/download/v0.1.5/moonshine-voice-macos-arm64.tar.gz
  mv "$ARCHIVE.part" "$ARCHIVE"
fi
[[ "$(shasum -a 256 "$ARCHIVE" | awk '{print $1}')" == 51151f98eb1b20b8fc141bab361a1574dbfdbef8300b632ee6679e373112e0f6 ]] || { echo 'Moonshine archive checksum mismatch.' >&2; exit 1; }
if [[ ! -f "$DEPS/moonshine/lib/libmoonshine.a" ]]; then
  mkdir -p "$DEPS/moonshine"
  tar -xzf "$ARCHIVE" -C "$DEPS/moonshine" --strip-components=1
fi
WHISPER_COMMIT=d1be6fde11ac6e0407606b4e42fe72d34add8037
if [[ ! -d "$DEPS/whisper.cpp/.git" ]]; then
  git clone --depth 1 --branch v1.9.5 https://github.com/ggml-org/whisper.cpp.git "$DEPS/whisper.cpp"
fi
[[ "$(git -C "$DEPS/whisper.cpp" rev-parse HEAD)" == "$WHISPER_COMMIT" ]] || { echo 'Whisper source revision mismatch.' >&2; exit 1; }
CMAKE="${VOCO_CMAKE:-$(command -v cmake || true)}"
if [[ -z "$CMAKE" && -x "$HOME/Library/Caches/Voco/BuildTools/cmake/bin/cmake" ]]; then
  CMAKE="$HOME/Library/Caches/Voco/BuildTools/cmake/bin/cmake"
fi
[[ -x "$CMAKE" ]] || { echo 'Install CMake or set VOCO_CMAKE to its executable.' >&2; exit 1; }
"$CMAKE" -S "$DEPS/whisper.cpp" -B "$DEPS/whisper-build" -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_OSX_ARCHITECTURES=arm64 -DCMAKE_OSX_DEPLOYMENT_TARGET=26.0 \
  -DBUILD_SHARED_LIBS=OFF -DWHISPER_BUILD_TESTS=OFF -DWHISPER_BUILD_EXAMPLES=OFF \
  -DGGML_METAL=ON -DGGML_METAL_EMBED_LIBRARY=ON
"$CMAKE" --build "$DEPS/whisper-build" --config Release -j "$(sysctl -n hw.logicalcpu)"
export VOCO_MOONSHINE_INCLUDE="$DEPS/moonshine/include"
export VOCO_MOONSHINE_LIBRARY="$DEPS/moonshine/lib"
export VOCO_WHISPER_INCLUDE="$DEPS/whisper.cpp/include"
export VOCO_GGML_INCLUDE="$DEPS/whisper.cpp/ggml/include"
export VOCO_WHISPER_LIBRARY="$DEPS/whisper-build/src/libwhisper.a"
export VOCO_GGML_LIBRARY="$DEPS/whisper-build/ggml/src/libggml.a"
export VOCO_GGML_BASE_LIBRARY="$DEPS/whisper-build/ggml/src/libggml-base.a"
export VOCO_GGML_CPU_LIBRARY="$DEPS/whisper-build/ggml/src/libggml-cpu.a"
export VOCO_GGML_METAL_LIBRARY="$DEPS/whisper-build/ggml/src/ggml-metal/libggml-metal.a"
export VOCO_GGML_BLAS_LIBRARY="$DEPS/whisper-build/ggml/src/ggml-blas/libggml-blas.a"
swift build --package-path "$ROOT/native" --scratch-path "$BUILD/swiftpm" --configuration release --build-system swiftbuild
BINARY="$(swift build --package-path "$ROOT/native" --scratch-path "$BUILD/swiftpm" --configuration release --build-system swiftbuild --show-bin-path)/VocoNative"
APP="$BUILD/VocoNative.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BINARY" "$APP/Contents/MacOS/VocoNative"
cp "$ROOT/native/Info.plist" "$APP/Contents/Info.plist"
VERSION="$(node -p 'require(process.argv[1]).version' "$ROOT/package.json")"
plutil -replace CFBundleShortVersionString -string "$VERSION" "$APP/Contents/Info.plist"
plutil -replace CFBundleVersion -string "$VERSION" "$APP/Contents/Info.plist"
cp "$ROOT/Resources/Voco.icns" "$APP/Contents/Resources/"
IDENTITY="${VOCO_CODESIGN_IDENTITY:-}"
if [[ -z "$IDENTITY" && -f "$HOME/Library/Application Support/Voco/signing-identity" ]]; then
  IDENTITY="$(cat "$HOME/Library/Application Support/Voco/signing-identity")"
fi
xattr -cr "$APP"
codesign --force --options runtime --timestamp=none --entitlements "$ROOT/Resources/entitlements.mac.plist" --sign "${IDENTITY:--}" "$APP"
codesign --verify --deep --strict "$APP"
echo "Built $APP"
