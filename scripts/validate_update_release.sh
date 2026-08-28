#!/bin/bash

set -euo pipefail

usage() {
  echo "Usage: $0 /path/to/prepared-release [--require-macos-verification]" >&2
}

if (( $# < 1 || $# > 2 )); then
  usage
  exit 2
fi

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
release_dir="${1%/}"
verification_mode="${2:---metadata-only}"
info_path="${release_dir}/release-info.txt"
temporary_dir=""

if [[ "$verification_mode" != "--metadata-only" &&
      "$verification_mode" != "--require-macos-verification" ]]; then
  usage
  exit 2
fi

if [[ ! -d "$release_dir" || ! -f "$info_path" ]]; then
  echo "Prepared release or release-info.txt not found: ${release_dir}" >&2
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

version="$(read_info version)"
build_number="$(read_info build)"
tag="$(read_info tag)"
revision="$(read_info revision)"
channel="$(read_info channel)"
zip_name="$(read_info zip)"
dmg_name="$(read_info dmg)"
source_name="$(read_info source)"
notes_name="$(read_info notes)"
appcast_name="$(read_info appcast)"
public_key="$(read_info sparkle_public_key)"
expected_feed_url="https://github.com/rawya-ai-player/client-macos/releases/latest/download/appcast.xml"

if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "Invalid release version: ${version}" >&2
  exit 1
fi
if [[ ! "$build_number" =~ ^[1-9][0-9]*$ ]]; then
  echo "Invalid release build number: ${build_number}" >&2
  exit 1
fi
if [[ "$channel" != "stable" ||
      ( "$tag" != "rawya-v${version}" &&
        "$tag" != "rawya-v${version}-build${build_number}" ) ]]; then
  echo "Only stable Rawya release tags are supported; found ${tag} (${channel})." >&2
  exit 1
fi
if [[ ! "$revision" =~ ^[0-9a-f]{40}$ ]]; then
  echo "Invalid release revision: ${revision}" >&2
  exit 1
fi
if [[ ! "$public_key" =~ ^[A-Za-z0-9+/]{43}=$ ]]; then
  echo "Invalid Sparkle public key in release-info.txt" >&2
  exit 1
fi

expected_zip="Rawya-${version}-${build_number}.zip"
expected_dmg="Rawya-${version}-${build_number}.dmg"
expected_source="Rawya-${version}-${build_number}-source.tar.gz"
if [[ "$zip_name" != "$expected_zip" || "$dmg_name" != "$expected_dmg" ||
      "$source_name" != "$expected_source" || "$notes_name" != "release-notes.md" ||
      "$appcast_name" != "appcast.xml" ]]; then
  echo "Release filenames do not match version ${version} build ${build_number}." >&2
  exit 1
fi

for required_file in "$zip_name" "$dmg_name" "$source_name" "$notes_name" \
    "$appcast_name" SHA256SUMS; do
  if [[ ! -f "${release_dir}/${required_file}" ]]; then
    echo "Release file missing: ${required_file}" >&2
    exit 1
  fi
done

if command -v shasum >/dev/null 2>&1; then
  (cd "$release_dir" && shasum -a 256 -c SHA256SUMS)
elif command -v sha256sum >/dev/null 2>&1; then
  (cd "$release_dir" && sha256sum -c SHA256SUMS)
else
  echo "Neither shasum nor sha256sum is available." >&2
  exit 1
fi

if ! command -v xmllint >/dev/null 2>&1; then
  echo "xmllint is required to validate the Sparkle appcast." >&2
  exit 1
fi

appcast_path="${release_dir}/${appcast_name}"
xmllint --noout "$appcast_path"
feed_signature_block="$(xmllint --xpath \
  "string((//comment()[contains(., 'sparkle-signatures:')])[1])" \
  "$appcast_path")"
if [[ "$feed_signature_block" != *"edSignature:"* ||
      "$feed_signature_block" != *"length:"* ]]; then
  echo "Sparkle appcast is not signed." >&2
  exit 1
fi
xpath_string() {
  xmllint --xpath "string((//item/enclosure)[1]/@*[local-name()='${1}'])" "$appcast_path"
}

appcast_build="$(xpath_string version)"
appcast_version="$(xpath_string shortVersionString)"
appcast_url="$(xpath_string url)"
appcast_signature="$(xpath_string edSignature)"
appcast_length="$(xpath_string length)"
expected_url="https://github.com/rawya-ai-player/client-macos/releases/download/${tag}/${zip_name}"

if [[ "$appcast_build" != "$build_number" || "$appcast_version" != "$version" ]]; then
  echo "Appcast version does not match release-info.txt." >&2
  exit 1
fi
if [[ "$appcast_url" != "$expected_url" ]]; then
  echo "Unexpected appcast download URL: ${appcast_url}" >&2
  exit 1
fi
if [[ -z "$appcast_signature" || ! "$appcast_length" =~ ^[1-9][0-9]*$ ]]; then
  echo "Appcast enclosure is missing an EdDSA signature or length." >&2
  exit 1
fi

if [[ "$(uname -s)" == "Darwin" ]]; then
  actual_length="$(stat -f '%z' "${release_dir}/${zip_name}")"
else
  actual_length="$(stat -c '%s' "${release_dir}/${zip_name}")"
fi
if [[ "$appcast_length" != "$actual_length" ]]; then
  echo "Appcast enclosure length does not match ${zip_name}." >&2
  exit 1
fi

if [[ "$verification_mode" == "--require-macos-verification" ]]; then
  if [[ "$(uname -s)" != "Darwin" ]]; then
    echo "macOS verification requires Darwin." >&2
    exit 1
  fi
  temporary_dir="$(mktemp -d "${TMPDIR:-/tmp}/rawya-release-verification.XXXXXX")"
  ditto -x -k "${release_dir}/${zip_name}" "$temporary_dir"
  "${repo_root}/scripts/verify_distribution.sh" \
    "${temporary_dir}/Rawya.app" \
    --require-notarization
  archive_public_key="$(/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' \
    "${temporary_dir}/Rawya.app/Contents/Info.plist")"
  if [[ "$archive_public_key" != "$public_key" ]]; then
    echo "Sparkle public key in the update archive does not match release-info.txt." >&2
    exit 1
  fi
  archive_info_plist="${temporary_dir}/Rawya.app/Contents/Info.plist"
  archive_feed_url="$(/usr/libexec/PlistBuddy -c 'Print :SUFeedURL' "$archive_info_plist")"
  archive_allows_automatic_updates="$(/usr/libexec/PlistBuddy -c 'Print :SUAllowsAutomaticUpdates' "$archive_info_plist")"
  archive_requires_signed_feed="$(/usr/libexec/PlistBuddy -c 'Print :SURequireSignedFeed' "$archive_info_plist")"
  archive_verifies_before_extraction="$(/usr/libexec/PlistBuddy -c 'Print :SUVerifyUpdateBeforeExtraction' "$archive_info_plist")"
  if [[ "$archive_feed_url" != "$expected_feed_url" ||
        "$archive_allows_automatic_updates" != "true" ||
        "$archive_requires_signed_feed" != "true" ||
        "$archive_verifies_before_extraction" != "true" ]]; then
    echo "Rawya.app in the update archive has an invalid stable update configuration." >&2
    exit 1
  fi
  hdiutil verify "${release_dir}/${dmg_name}"
fi

echo "Rawya ${version} (${build_number}) release metadata passed ${verification_mode#--} verification"
