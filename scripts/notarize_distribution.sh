#!/bin/bash

set -euo pipefail

usage() {
  echo "Usage: $0 /path/to/Rawya.app" >&2
}

if (( $# != 1 )); then
  usage
  exit 2
fi

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
app_path="${1%/}"
artifact_dir="$(dirname "$app_path")"
notary_profile="${RAWYA_NOTARY_PROFILE:-rawya-notary}"
response_path="${artifact_dir}/notarization-response.json"
log_path="${artifact_dir}/notarization-log.json"
verification_dir=""

cleanup_verification() {
  if [[ -n "${verification_dir:-}" && -d "$verification_dir" ]]; then
    /usr/bin/trash "$verification_dir"
  fi
}
trap cleanup_verification EXIT

if [[ ! -d "$app_path" ]]; then
  echo "Rawya app not found: ${app_path}" >&2
  exit 1
fi

if [[ "${RAWYA_CONFIRM_NOTARIZATION:-}" != "NOTARIZE_RAWYA" ]]; then
  echo "Notarization requires explicit confirmation." >&2
  echo "Set RAWYA_CONFIRM_NOTARIZATION=NOTARIZE_RAWYA for an approved submission." >&2
  exit 1
fi

if ! xcrun notarytool history \
    --keychain-profile "$notary_profile" \
    --output-format json >/dev/null 2>&1; then
  echo "Notary keychain profile is missing or invalid: ${notary_profile}" >&2
  echo "Create it with 'xcrun notarytool store-credentials ${notary_profile}' before submitting." >&2
  exit 1
fi

"${repo_root}/scripts/verify_distribution.sh" "$app_path"

version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "${app_path}/Contents/Info.plist")"
build_number="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "${app_path}/Contents/Info.plist")"
submission_zip="${artifact_dir}/Rawya-${version}-${build_number}-notarization-upload.zip"
final_zip="${artifact_dir}/Rawya-${version}-${build_number}-notarized.zip"

ditto -c -k --sequesterRsrc --keepParent "$app_path" "$submission_zip"

echo "Submitting Rawya ${version} (${build_number}) for notarization"
if ! xcrun notarytool submit "$submission_zip" \
    --keychain-profile "$notary_profile" \
    --wait \
    --output-format json > "$response_path"; then
  submission_id="$(plutil -extract id raw -o - "$response_path" 2>/dev/null || true)"
  if [[ -n "$submission_id" ]]; then
    xcrun notarytool log "$submission_id" "$log_path" \
      --keychain-profile "$notary_profile" || true
  fi
  echo "Notarization request failed; see ${response_path} and ${log_path}." >&2
  exit 1
fi

notary_status="$(plutil -extract status raw -o - "$response_path")"
if [[ "$notary_status" != "Accepted" ]]; then
  submission_id="$(plutil -extract id raw -o - "$response_path" 2>/dev/null || true)"
  if [[ -n "$submission_id" ]]; then
    xcrun notarytool log "$submission_id" "$log_path" \
      --keychain-profile "$notary_profile" || true
  fi
  echo "Notarization was not accepted: ${notary_status}" >&2
  exit 1
fi

xcrun stapler staple "$app_path"
"${repo_root}/scripts/verify_distribution.sh" "$app_path" --require-notarization
ditto -c -k --sequesterRsrc --keepParent "$app_path" "$final_zip"

verification_dir="$(mktemp -d "${artifact_dir}/.verification.XXXXXX")"
ditto -x -k "$final_zip" "$verification_dir"
"${repo_root}/scripts/verify_distribution.sh" \
  "${verification_dir}/Rawya.app" \
  --require-notarization
/usr/bin/trash "$verification_dir"
verification_dir=""

info_path="${artifact_dir}/distribution-info.txt"
if [[ -f "$info_path" ]]; then
  sed -i '' 's/^notarized=no$/notarized=yes/' "$info_path"
  {
    echo "notarized_at=$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
    echo "notary_profile=${notary_profile}"
  } >> "$info_path"
fi

signed_zip="${artifact_dir}/Rawya-${version}-${build_number}-signed.zip"
for intermediate_zip in "$signed_zip" "$submission_zip"; do
  if [[ -f "$intermediate_zip" ]]; then
    /usr/bin/trash "$intermediate_zip"
  fi
done

"${repo_root}/scripts/prune_distribution_builds.sh" "$(basename "$artifact_dir")"

echo "Notarized app: ${app_path}"
echo "Distribution archive: ${final_zip}"
