#!/bin/bash
set -euo pipefail
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
cd "$project_dir"
cargo fmt --all -- --check
runtime_dependencies="$(cargo tree --locked --edges normal --prefix none --format '{p}')"
if ! grep -Eq '^gpui v' <<< "$runtime_dependencies"; then
    echo 'The dashboard must use GPUI.' >&2
    exit 1
fi
if grep -E '^(eframe|egui|wry|tauri|web-view) v' <<< "$runtime_dependencies"; then
    echo 'The native runtime contains an unsupported UI renderer.' >&2
    exit 1
fi
cargo clippy --locked --all-targets -- -D warnings
cargo test --locked --all-targets
cargo build --locked
if [[ "${VOCO_VERIFY_UI:-0}" == 1 ]]; then
    scratch="$(mktemp -d "${TMPDIR:-/tmp}/voco-rust-verify.XXXXXX")"
    VOCO_DATA_DIR="$scratch/profile" target/debug/voco --verify-ui "$scratch/ui"
    printf 'UI screenshots and report: %s\n' "$scratch/ui"
fi
if [[ -n "${VOCO_VERIFY_AUDIO:-}" ]]; then
    for model in moonshine parakeet whisper; do
        target/debug/voco --transcribe "$model" "$VOCO_VERIFY_AUDIO"
    done
fi
