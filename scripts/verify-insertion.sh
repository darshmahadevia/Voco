#!/bin/bash
set -euo pipefail
diagnostic_file="$(mktemp "${TMPDIR:-/tmp}/voco-insertion.XXXXXX")"
trap 'rm -f "$diagnostic_file"' EXIT
verification_args=(--verify-insertion)
if test "$#" -gt 0; then
    verification_args+=(--audio-fixture "$1")
fi
open -W -n -a "$HOME/Applications/Voco.app" --stdout "$diagnostic_file" --args "${verification_args[@]}"
cat "$diagnostic_file"
grep -q '^Insertion 5: exact text verified$' "$diagnostic_file"
grep -q '^Live typing, corrections, and pause continuation verified$' "$diagnostic_file"
if test "$#" -gt 0; then
    grep -q '^Live speech: .* verified$' "$diagnostic_file"
fi
