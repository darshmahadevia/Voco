#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
env -u ELECTRON_RUN_AS_NODE ./node_modules/.bin/electron scripts/generate-brand.cjs
mkdir -p build/Voco.iconset
for size in 16 32 128 256 512; do
  sips -z "$size" "$size" Resources/Brand/voco-app.png --out "build/Voco.iconset/icon_${size}x${size}.png" >/dev/null
  doubled=$((size * 2))
  sips -z "$doubled" "$doubled" Resources/Brand/voco-app.png --out "build/Voco.iconset/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns build/Voco.iconset -o Resources/Voco.icns
