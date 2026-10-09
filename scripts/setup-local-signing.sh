#!/bin/bash
set -euo pipefail
umask 077
identity="Voco Local Development"
keychain="$HOME/Library/Keychains/login.keychain-db"
config_dir="$HOME/Library/Application Support/Voco"
temporary_dir="$(mktemp -d "${TMPDIR:-/tmp}/voco-signing.XXXXXX")"
trap 'rm -rf "$temporary_dir"' EXIT

if ! security find-certificate -c "$identity" "$keychain" >/dev/null 2>&1; then
    cat > "$temporary_dir/certificate.conf" <<'CONFIG'
[req]
distinguished_name = dn
x509_extensions = signing
prompt = no
[dn]
CN = Voco Local Development
[signing]
basicConstraints = critical,CA:FALSE
keyUsage = critical,digitalSignature
extendedKeyUsage = codeSigning
CONFIG
    openssl req -new -x509 -newkey rsa:3072 -sha256 -nodes -days 3650 \
        -config "$temporary_dir/certificate.conf" \
        -keyout "$temporary_dir/private.key" -out "$temporary_dir/certificate.pem" \
        2> "$temporary_dir/openssl.log"
    export VOCO_SIGNING_EXPORT_PASSWORD="$(openssl rand -hex 32)"
    openssl pkcs12 -export -inkey "$temporary_dir/private.key" \
        -in "$temporary_dir/certificate.pem" -name "$identity" \
        -out "$temporary_dir/signing.p12" -passout env:VOCO_SIGNING_EXPORT_PASSWORD \
        -keypbe PBE-SHA1-3DES -certpbe PBE-SHA1-3DES -macalg sha1
    security import "$temporary_dir/signing.p12" -k "$keychain" -P "$VOCO_SIGNING_EXPORT_PASSWORD" -T /usr/bin/codesign
    unset VOCO_SIGNING_EXPORT_PASSWORD
else
    security find-certificate -c "$identity" -p "$keychain" > "$temporary_dir/certificate.pem"
fi
if ! security find-identity -v -p codesigning "$keychain" | rg -F "$identity" >/dev/null; then
    security add-trusted-cert -r trustRoot -p codeSign -k "$keychain" "$temporary_dir/certificate.pem"
fi
if ! security find-identity -v -p codesigning "$keychain" | rg -F "$identity" >/dev/null; then
    echo "The certificate does not have a usable signing key. Check login Keychain." >&2
    exit 1
fi
mkdir -p "$config_dir"
printf '%s\n' "$identity" > "$config_dir/signing-identity"
printf 'Configured local signing: %s\n' "$identity"
