#!/bin/bash
set -euo pipefail
app_dir="$HOME/Applications/Voco.app"
diagnostic_file="$(mktemp "${TMPDIR:-/tmp}/voco-restart.XXXXXX")"
trap 'rm -f "$diagnostic_file"' EXIT

while IFS= read -r voco_pid; do
    if test "$(ps -p "$voco_pid" -o comm= || true)" = "$app_dir/Contents/MacOS/Voco"; then
        printf 'Quit the installed Voco app before running the restart check.\n' >&2
        exit 1
    fi
done < <(pgrep -x Voco || true)
open -W -n -a "$app_dir" --stdout "$diagnostic_file" --args --verify-restart
cat "$diagnostic_file"
previous_pid="$(sed -n 's/^Restarting Voco process //p' "$diagnostic_file")"
if ! [[ "$previous_pid" =~ ^[0-9]+$ ]] || kill -0 "$previous_pid" 2>/dev/null; then
    printf 'The original Voco process did not exit after relaunch.\n' >&2
    exit 1
fi
running_count=0
while IFS= read -r voco_pid; do
    if test "$(ps -p "$voco_pid" -o comm= || true)" = "$app_dir/Contents/MacOS/Voco"; then
        running_count=$((running_count + 1))
        printf 'Relaunched installed Voco process %s\n' "$voco_pid"
    fi
done < <(pgrep -x Voco || true)
test "$running_count" -eq 1
printf 'Installed app restart: PASS\n'
