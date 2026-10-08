#!/bin/bash
set -euo pipefail
app_dir="$HOME/Applications/Voco.app"
diagnostic_file="$(mktemp "${TMPDIR:-/tmp}/voco-shortcut.XXXXXX")"
trap 'rm -f "$diagnostic_file"' EXIT

open -W -n -a "$app_dir" --stdout "$diagnostic_file" --args --check-shortcut
cat "$diagnostic_file"
grep -q '^Global shortcut: available$' "$diagnostic_file"
