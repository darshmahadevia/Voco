#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export VOCO_VERIFY_DESKTOP_APP="${VOCO_VERIFY_DESKTOP_APP:-$HOME/Applications/Voco.app}"
if [[ -n "${VOCO_VERIFY_AUDIO_FIXTURE:-}" ]]; then
  : "${VOCO_VERIFY_EXPECTED_TRANSCRIPT:?Set the literal expected audio transcript.}"
  export VOCO_VERIFY_MODEL_DIRECTORY="${VOCO_VERIFY_MODEL_DIRECTORY:-$HOME/Library/Application Support/Voco/models/moonshine-medium-streaming-en}"
fi
SCRATCH="$(mktemp -d "${TMPDIR:-/tmp}/voco-buffered-check.XXXXXX")"
trap 'rm -rf "$SCRATCH"' EXIT
swiftc -swift-version 6 -parse-as-library native/Tests/buffered-native-editor.swift -o "$SCRATCH/editor"
"$SCRATCH/editor" "$VOCO_VERIFY_DESKTOP_APP"
env -u ELECTRON_RUN_AS_NODE node_modules/.bin/electron scripts/verify-buffered-insertion.cjs
