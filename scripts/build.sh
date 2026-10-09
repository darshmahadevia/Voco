#!/bin/bash
set -euo pipefail
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
cd "$project_dir"
npm run pack
mkdir -p "$project_dir/build"
if test -L "$project_dir/build/Voco.app"; then
    rm "$project_dir/build/Voco.app"
elif test -e "$project_dir/build/Voco.app"; then
    echo "Expected build/Voco.app to be a build link." >&2
    exit 1
fi
ln -s "$project_dir/release/mac-arm64/Voco.app" "$project_dir/build/Voco.app"
printf 'Built %s/build/Voco.app\n' "$project_dir"
