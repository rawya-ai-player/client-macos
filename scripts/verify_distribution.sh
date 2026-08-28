#!/bin/bash

set -euo pipefail

usage() {
  echo "Usage: $0 /path/to/Rawya.app [--require-notarization]" >&2
}

if (( $# < 1 || $# > 2 )); then
  usage
  exit 2
fi

app_path="${1%/}"
verification_mode="${2:---signed-only}"
expected_team="${RAWYA_DEVELOPMENT_TEAM:-W684N2R45F}"
expected_bundle_id="${RAWYA_BUNDLE_ID:-app.rawya.player}"
extension_path="${app_path}/Contents/PlugIns/OpenInIINA.appex"

if [[ "$verification_mode" != "--signed-only" && "$verification_mode" != "--require-notarization" ]]; then
  usage
  exit 2
fi

if [[ ! -d "$app_path" ]]; then
  echo "Rawya app not found: ${app_path}" >&2
  exit 1
fi

signature_details() {
  codesign -dvvv "$1" 2>&1
}

assert_distribution_signature() {
  local code_path="$1"
  local details

  details="$(signature_details "$code_path")"
  if grep -Fq 'Signature=adhoc' <<< "$details"; then
    echo "Ad-hoc signature found: ${code_path}" >&2
    exit 1
  fi
  if ! grep -Fq 'Authority=Developer ID Application:' <<< "$details"; then
    echo "Developer ID Application signature missing: ${code_path}" >&2
    exit 1
  fi
  if ! grep -Fq "TeamIdentifier=${expected_team}" <<< "$details"; then
    echo "Unexpected signing team for ${code_path}; expected ${expected_team}" >&2
    exit 1
  fi
  if ! grep -Eq 'flags=.*\(.*runtime.*\)' <<< "$details"; then
    echo "Hardened Runtime is not enabled: ${code_path}" >&2
    exit 1
  fi
  if ! grep -Fq 'Timestamp=' <<< "$details"; then
    echo "Secure timestamp is missing: ${code_path}" >&2
    exit 1
  fi
}

assert_no_debug_entitlement() {
  local code_path="$1"
  local entitlements

  entitlements="$(codesign -d --entitlements :- "$code_path" 2>/dev/null || true)"
  if grep -A1 -Fq '<key>com.apple.security.get-task-allow</key>' <<< "$entitlements" &&
      grep -A1 -F '<key>com.apple.security.get-task-allow</key>' <<< "$entitlements" | grep -Fq '<true/>'; then
    echo "Debug entitlement is enabled: ${code_path}" >&2
    exit 1
  fi
}

echo "Verifying Rawya distribution signature"
codesign --verify --deep --strict "$app_path"
assert_distribution_signature "$app_path"
assert_no_debug_entitlement "$app_path"

bundle_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "${app_path}/Contents/Info.plist")"
if [[ "$bundle_id" != "$expected_bundle_id" ]]; then
  echo "Unexpected app bundle identifier: ${bundle_id}" >&2
  exit 1
fi

if [[ ! -d "$extension_path" ]]; then
  echo "Bundled Safari extension not found: ${extension_path}" >&2
  exit 1
fi
codesign --verify --strict "$extension_path"
assert_distribution_signature "$extension_path"
assert_no_debug_entitlement "$extension_path"

extension_bundle_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "${extension_path}/Contents/Info.plist")"
if [[ "$extension_bundle_id" != "${expected_bundle_id}.OpenInIINA" ]]; then
  echo "Unexpected extension bundle identifier: ${extension_bundle_id}" >&2
  exit 1
fi

while IFS= read -r -d '' candidate; do
  if file -b "$candidate" | grep -Fq 'Mach-O'; then
    codesign --verify --strict "$candidate"
    details="$(signature_details "$candidate")"
    if grep -Fq 'Signature=adhoc' <<< "$details"; then
      echo "Ad-hoc nested code found: ${candidate}" >&2
      exit 1
    fi
    if ! grep -Fq 'Authority=Developer ID Application:' <<< "$details"; then
      echo "Developer ID signature missing from nested code: ${candidate}" >&2
      exit 1
    fi
    if ! grep -Fq "TeamIdentifier=${expected_team}" <<< "$details"; then
      echo "Unexpected signing team for nested code: ${candidate}" >&2
      exit 1
    fi
    if ! grep -Fq 'Timestamp=' <<< "$details"; then
      echo "Secure timestamp missing from nested code: ${candidate}" >&2
      exit 1
    fi
    if otool -hv "$candidate" | awk '$5 == "EXECUTE" { found = 1 } END { exit !found }' &&
        ! grep -Eq 'flags=.*\(.*runtime.*\)' <<< "$details"; then
      echo "Hardened Runtime missing from nested executable: ${candidate}" >&2
      exit 1
    fi
  fi
done < <(find "${app_path}/Contents" -type f -print0)

version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "${app_path}/Contents/Info.plist")"
build_number="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "${app_path}/Contents/Info.plist")"

if [[ "$verification_mode" == "--require-notarization" ]]; then
  echo "Validating stapled notarization ticket"
  xcrun stapler validate "$app_path"
  spctl --assess --type execute --verbose=2 "$app_path"
fi

echo "Rawya ${version} (${build_number}) passed ${verification_mode#--} verification"
