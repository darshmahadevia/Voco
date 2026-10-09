#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [[ "$#" -lt 1 ]]; then
  echo "Usage: $0 'exact disposable draft text' [--audio-fixture PATH --model-directory PATH]" >&2
  echo "Focus a disposable native, browser, or Electron field. A selection will be preserved." >&2
  exit 2
fi
LOG_DIRECTORY="$(mktemp -d "${TMPDIR:-/tmp}/voco-live-check.XXXXXX")"
trap 'rm -rf "$LOG_DIRECTORY"' EXIT
open -W -g -n "$ROOT/native/build/VocoNative.app" \
  --stdout "$LOG_DIRECTORY/output.log" --stderr "$LOG_DIRECTORY/error.log" \
  --args --verify-live-insertion "$@"
cat "$LOG_DIRECTORY/output.log" "$LOG_DIRECTORY/error.log"
rg -q '^Live insertion checks: PASS' "$LOG_DIRECTORY/output.log"
