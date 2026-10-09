#!/bin/bash
set -euo pipefail
if test "$#" -ne 1; then
    printf 'Usage: %s "exact disposable draft text"\nPlace the caret at the end of that draft in the target app. Nothing is submitted.\n' "$0" >&2
    exit 1
fi
verification_directory="$(mktemp -d "${TMPDIR:-/tmp}/voco-focused-insertion.XXXXXX")"
diagnostic_file="$verification_directory/output.log"
trap 'rm -rf "$verification_directory"' EXIT
open -W -g -n -a "$HOME/Applications/Voco.app" --stdout "$diagnostic_file" \
    --args --verify-desktop "--verification-directory=$verification_directory" \
    --verify-live-insertion "$1"
cat "$diagnostic_file"
grep -q '^Live insertion checks: PASS$' "$diagnostic_file"
