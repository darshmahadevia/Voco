#!/bin/bash
set -euo pipefail
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
cd "$project_dir"

if test "$(uname -s)" != Darwin; then
    printf 'Voco local push updates require macOS.\n' >&2
    exit 1
fi
configured_hooks="$(git config --get core.hooksPath || true)"
if test -n "$configured_hooks" && test "$configured_hooks" != .githooks; then
    printf 'Existing core.hooksPath=%s was left unchanged. Add the Voco pre-push hook to your existing hook workflow.\n' "$configured_hooks" >&2
    exit 1
fi
if test -z "$configured_hooks"; then
    for hook in "$(git rev-parse --git-path hooks)"/*; do
        case "$hook" in *.sample) continue ;; esac
        if test -f "$hook" && test -x "$hook"; then
            printf 'Existing Git hooks were left unchanged. Add the Voco pre-push hook to your existing hook workflow.\n' >&2
            exit 1
        fi
    done
fi
git config --local core.hooksPath .githooks
printf 'Enabled: pushing the checked-out branch to GitHub builds, installs, and opens Voco locally.\n'
