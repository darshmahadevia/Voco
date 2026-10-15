#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEPS="$ROOT/native/build/dependencies"
MODEL="${1:-$HOME/Library/Application Support/Voco/models/whisper-large-v3-turbo}"
SCRATCH="$(mktemp -d "${TMPDIR:-/tmp}/voco-whisper-cancellation.XXXXXX")"
trap 'rm -rf "$SCRATCH"' EXIT
# Use only existing libraries. Do not invoke or contend with the main app build.
LINK=()
for archive in src/libwhisper.a ggml/src/libggml.a ggml/src/libggml-base.a ggml/src/libggml-cpu.a \
  ggml/src/ggml-metal/libggml-metal.a ggml/src/ggml-blas/libggml-blas.a; do
  LINK+=(-Xlinker -force_load -Xlinker "$DEPS/whisper-build/$archive")
done
# Omit factories for unrelated backends from the focused catalog copy.
python3 - "$ROOT/native/Sources/ModelCatalog.swift" "$SCRATCH/ModelCatalog.swift" <<'PYTHON'
import sys
source = open(sys.argv[1]).read()
open(sys.argv[2], 'w').write(source[:source.index('    static func makeEngine(')] + '}\n')
PYTHON
xcrun swiftc -swift-version 6 -parse-as-library -target "$(uname -m)-apple-macosx26.0" \
  -I "$ROOT/native/Whisper" -Xcc -I -Xcc "$DEPS/whisper.cpp/include" \
  -Xcc -I -Xcc "$DEPS/whisper.cpp/ggml/include" \
  "$ROOT/native/Sources/SessionTypes.swift" "$SCRATCH/ModelCatalog.swift" \
  "$ROOT/native/Sources/TranscriptLedger.swift" "$ROOT/native/Sources/WhisperEngine.swift" \
  "$ROOT/native/Tests/WhisperCancellationCheck.swift" "${LINK[@]}" \
  -framework Accelerate -framework Foundation -framework AVFoundation -framework Metal -lc++ \
  -o "$SCRATCH/check"
say -v Samantha -o "$SCRATCH/phrase.aiff" 'The quick brown fox jumps over the lazy dog. This is a local dictation cancellation test.'
afconvert -f WAVE -d LEI16@16000 -c 1 "$SCRATCH/phrase.aiff" "$SCRATCH/phrase.wav"
python3 - "$SCRATCH/check" "$MODEL" "$SCRATCH/phrase.wav" <<'PYTHON'
import subprocess
import sys
subprocess.run(sys.argv[1:], check=True, timeout=180)
PYTHON
