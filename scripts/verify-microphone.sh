#!/bin/bash
set -euo pipefail
verification_directory="$(mktemp -d "${TMPDIR:-/tmp}/voco-microphone.XXXXXX")"
trap 'rm -rf "$verification_directory"' EXIT
model_directory="${VOCO_VERIFY_MODEL_DIRECTORY:-$HOME/Library/Application Support/Voco/models/moonshine-medium-streaming-en}"
env -u ELECTRON_RUN_AS_NODE open -W -g -n -a "$HOME/Applications/Voco.app" \
    --stdout "$verification_directory/output.log" --stderr "$verification_directory/error.log" \
    --args --verify-desktop "--verification-directory=$verification_directory" \
    "--verification-model-directory=$model_directory" --verify-microphone
node - "$verification_directory" <<'JS'
const { readFileSync } = require('node:fs');
const { join } = require('node:path');
const directory = process.argv[2];
let report;
try { report = JSON.parse(readFileSync(join(directory, 'microphone.json'), 'utf8')); }
catch { throw new Error(readFileSync(join(directory, 'error.log'), 'utf8') || 'No microphone report was produced.'); }
if (report.status !== 'pass' || report.microphone !== 'granted' || !(report.audioCallbacks > 0)) {
  throw new Error(report.error || 'The microphone did not deliver audio.');
}
console.log(`Microphone capture: PASS (${report.audioCallbacks} audio callbacks, ${report.speechCallbacks} speech callbacks)`);
JS
