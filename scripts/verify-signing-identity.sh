#!/bin/bash
set -euo pipefail
identity="${VOCO_CODESIGN_IDENTITY:-$(cat "$HOME/Library/Application Support/Voco/signing-identity")}"
temporary_dir="$(mktemp -d "${TMPDIR:-/tmp}/voco-signing-check.XXXXXX")"
trap 'rm -rf "$temporary_dir"' EXIT
for version in 1 2; do
    printf 'print("Voco signing version %s")\n' "$version" > "$temporary_dir/check.swift"
    swiftc "$temporary_dir/check.swift" -o "$temporary_dir/version-$version"
    codesign --force --sign "$identity" --identifier org.vocoapp.Voco.SigningCheck "$temporary_dir/version-$version"
    codesign --verify --strict "$temporary_dir/version-$version"
    codesign -d -r- "$temporary_dir/version-$version" 2>&1 | sed -n 's/^.*designated => //p' > "$temporary_dir/requirement-$version"
    codesign -dv --verbose=4 "$temporary_dir/version-$version" 2>&1 | sed -n 's/^CDHash=//p' > "$temporary_dir/hash-$version"
done
test -s "$temporary_dir/requirement-1"
cmp "$temporary_dir/requirement-1" "$temporary_dir/requirement-2"
if cmp -s "$temporary_dir/hash-1" "$temporary_dir/hash-2"; then
    echo 'The signing check requires different binaries.' >&2
    exit 1
fi
echo 'PASS: changed binaries retain the same certificate signing requirement.'
