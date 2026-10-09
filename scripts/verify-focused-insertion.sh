#!/bin/bash
set -euo pipefail
if test "$#" -ne 1; then
    printf 'Usage: %s "exact disposable draft text"\nPlace the caret at the end of that draft in the target app. Nothing is submitted.\n' "$0" >&2
    exit 1
fi
diagnostic_file="$(mktemp "${TMPDIR:-/tmp}/voco-focused-insertion.XXXXXX")"
trap 'rm -f "$diagnostic_file"' EXIT
open -W -n -a "$HOME/Applications/Voco.app" --stdout "$diagnostic_file" \
    --args --verify-focused-insertion "$1"
cat "$diagnostic_file"
grep -q '^Focused insertion checks: PASS$' "$diagnostic_file"
