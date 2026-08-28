#!/bin/bash

set -euo pipefail

usage() {
  echo "Usage: $0 /path/to/prepared-release" >&2
}

if (( $# != 1 )); then
  usage
  exit 2
fi

release_dir="${1%/}"
info_path="${release_dir}/release-info.txt"
appcast_path="${release_dir}/appcast.xml"
temporary_dir=""

if [[ ! -f "$info_path" || ! -f "$appcast_path" ]]; then
  echo "Prepared release metadata or appcast not found: ${release_dir}" >&2
  exit 1
fi
if ! command -v xmllint >/dev/null 2>&1; then
  echo "xmllint is required to verify Sparkle signatures." >&2
  exit 1
fi

if [[ -n "${RAWYA_OPENSSL:-}" ]]; then
  openssl_bin="$RAWYA_OPENSSL"
elif [[ -x /opt/homebrew/bin/openssl ]]; then
  openssl_bin=/opt/homebrew/bin/openssl
else
  openssl_bin="$(command -v openssl || true)"
fi
if [[ -z "$openssl_bin" || ! -x "$openssl_bin" ]]; then
  echo "OpenSSL 3 is required to verify Sparkle signatures." >&2
  exit 1
fi
if ! "$openssl_bin" version | grep -Eq '^OpenSSL ([3-9]|[1-9][0-9])\.'; then
  echo "OpenSSL 3 or newer is required; found: $("$openssl_bin" version)" >&2
  exit 1
fi

cleanup() {
  if [[ -n "${temporary_dir:-}" && -d "$temporary_dir" ]]; then
    rm -rf "$temporary_dir"
  fi
}
trap cleanup EXIT

read_info() {
  local key="$1"
  awk -F= -v key="$key" '$1 == key { sub(/^[^=]*=/, ""); print; found = 1; exit } END { exit !found }' "$info_path"
}

zip_name="$(read_info zip)"
public_key="$(read_info sparkle_public_key)"
if [[ -n "${RAWYA_EXPECTED_SPARKLE_PUBLIC_KEY:-}" &&
      "$public_key" != "$RAWYA_EXPECTED_SPARKLE_PUBLIC_KEY" ]]; then
  echo "Release Sparkle public key does not match the expected application key." >&2
  exit 1
fi
if [[ ! -f "${release_dir}/${zip_name}" ]]; then
  echo "Sparkle update archive not found: ${zip_name}" >&2
  exit 1
fi

temporary_dir="$(mktemp -d "${TMPDIR:-/tmp}/rawya-sparkle-signatures.XXXXXX")"
{
  printf '\x30\x2a\x30\x05\x06\x03\x2b\x65\x70\x03\x21\x00'
  printf '%s' "$public_key" | "$openssl_bin" base64 -d -A
} > "${temporary_dir}/public.der"
"$openssl_bin" pkey \
  -pubin \
  -inform DER \
  -in "${temporary_dir}/public.der" \
  -out "${temporary_dir}/public.pem"

archive_signature="$(xmllint --xpath \
  "string((//item/enclosure)[1]/@*[local-name()='edSignature'])" \
  "$appcast_path")"
printf '%s' "$archive_signature" | \
  "$openssl_bin" base64 -d -A > "${temporary_dir}/archive.signature"
"$openssl_bin" pkeyutl \
  -verify \
  -pubin \
  -inkey "${temporary_dir}/public.pem" \
  -rawin \
  -in "${release_dir}/${zip_name}" \
  -sigfile "${temporary_dir}/archive.signature"

feed_signature_block="$(xmllint --xpath \
  "string((//comment()[contains(., 'sparkle-signatures:')])[1])" \
  "$appcast_path")"
feed_signature="$(printf '%s\n' "$feed_signature_block" | \
  awk -F': *' '$1 == "edSignature" { print $2; exit }')"
feed_length="$(printf '%s\n' "$feed_signature_block" | \
  awk -F': *' '$1 == "length" { print $2; exit }')"
if [[ -z "$feed_signature" || ! "$feed_length" =~ ^[1-9][0-9]*$ ]]; then
  echo "Signed Sparkle feed block is invalid." >&2
  exit 1
fi

head -c "$feed_length" "$appcast_path" > "${temporary_dir}/appcast-content.xml"
printf '%s' "$feed_signature" | \
  "$openssl_bin" base64 -d -A > "${temporary_dir}/appcast.signature"
"$openssl_bin" pkeyutl \
  -verify \
  -pubin \
  -inkey "${temporary_dir}/public.pem" \
  -rawin \
  -in "${temporary_dir}/appcast-content.xml" \
  -sigfile "${temporary_dir}/appcast.signature"

echo "Sparkle archive and appcast Ed25519 signatures are valid"
