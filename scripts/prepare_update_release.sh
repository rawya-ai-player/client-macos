#!/bin/bash

set -euo pipefail

usage() {
  echo "Usage: $0 /path/to/Rawya.app /path/to/release-notes.md" >&2
}

if (( $# != 2 )); then
  usage
  exit 2
fi

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
app_path="${1%/}"
release_notes="$2"
artifact_dir="$(dirname "$app_path")"
branch="$(git -C "$repo_root" branch --show-current)"
revision="$(git -C "$repo_root" rev-parse HEAD)"
sparkle_account="${RAWYA_SPARKLE_KEY_ACCOUNT:-rawya}"
source_packages="${RAWYA_SOURCE_PACKAGES:-${HOME}/Library/Developer/Rawya/BuildCache/SourcePackages}"
sparkle_bin_dir="${RAWYA_SPARKLE_BIN_DIR:-${source_packages}/artifacts/sparkle/Sparkle/bin}"
temporary_dir=""

if [[ ! -d "$app_path" || ! -f "$release_notes" ]]; then
  echo "Rawya.app or release notes not found." >&2
  usage
  exit 1
fi
if [[ "$branch" != "main" && "${RAWYA_ALLOW_NON_MAIN:-0}" != "1" ]]; then
  echo "Release preparation must run from main; current branch is ${branch}." >&2
  exit 1
fi
if [[ -n "$(git -C "$repo_root" status --porcelain)" && "${RAWYA_ALLOW_DIRTY:-0}" != "1" ]]; then
  echo "Release preparation requires a clean worktree." >&2
  exit 1
fi

for tool in generate_appcast generate_keys sign_update; do
  if [[ ! -x "${sparkle_bin_dir}/${tool}" ]]; then
    echo "Sparkle release tool not found: ${sparkle_bin_dir}/${tool}" >&2
    echo "Resolve Swift packages or set RAWYA_SPARKLE_BIN_DIR." >&2
    exit 1
  fi
done

"${repo_root}/scripts/verify_distribution.sh" "$app_path" --require-notarization

info_plist="${app_path}/Contents/Info.plist"
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$info_plist")"
build_number="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$info_plist")"
public_key="$(/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' "$info_plist")"
feed_url="$(/usr/libexec/PlistBuddy -c 'Print :SUFeedURL' "$info_plist")"
allows_automatic_updates="$(/usr/libexec/PlistBuddy -c 'Print :SUAllowsAutomaticUpdates' "$info_plist")"
requires_signed_feed="$(/usr/libexec/PlistBuddy -c 'Print :SURequireSignedFeed' "$info_plist")"
verifies_before_extraction="$(/usr/libexec/PlistBuddy -c 'Print :SUVerifyUpdateBeforeExtraction' "$info_plist")"
tag="${RAWYA_RELEASE_TAG:-rawya-v${version}}"
expected_feed_url="https://github.com/rawya-ai-player/client-macos/releases/latest/download/appcast.xml"

if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ || ! "$build_number" =~ ^[1-9][0-9]*$ ]]; then
  echo "Invalid app version or build number: ${version} (${build_number})" >&2
  exit 1
fi
if [[ "$tag" != "rawya-v${version}" &&
      "$tag" != "rawya-v${version}-build${build_number}" ]]; then
  echo "Stable release tag must match the app version and build; found ${tag}." >&2
  exit 1
fi
if [[ "$feed_url" != "$expected_feed_url" ||
      "$allows_automatic_updates" != "true" ||
      "$requires_signed_feed" != "true" ||
      "$verifies_before_extraction" != "true" ]]; then
  echo "Rawya.app has an invalid stable update configuration." >&2
  exit 1
fi
if [[ "$(git -C "$repo_root" cat-file -t "refs/tags/${tag}" 2>/dev/null || true)" != "tag" ]]; then
  echo "An annotated release tag is required: ${tag}" >&2
  exit 1
fi
tag_revision="$(git -C "$repo_root" rev-parse "refs/tags/${tag}^{commit}")"
if [[ "$tag_revision" != "$revision" ]]; then
  echo "Release tag ${tag} does not point to HEAD ${revision}." >&2
  exit 1
fi

build_revision="$(/usr/libexec/PlistBuddy -c 'Print :app.rawya.player.build.commit' "$info_plist" 2>/dev/null || true)"
if [[ -n "$build_revision" && "$revision" != "$build_revision"* ]]; then
  echo "Rawya.app was built from ${build_revision}, not release revision ${revision}." >&2
  exit 1
fi

source_zip="${artifact_dir}/Rawya-${version}-${build_number}-notarized.zip"
if [[ ! -f "$source_zip" ]]; then
  echo "Notarized update archive not found: ${source_zip}" >&2
  exit 1
fi

keychain_public_key="$("${sparkle_bin_dir}/generate_keys" --account "$sparkle_account" -p)"
if [[ "$keychain_public_key" != "$public_key" ]]; then
  echo "Sparkle keychain account ${sparkle_account} does not match Rawya.app SUPublicEDKey." >&2
  exit 1
fi

release_dir="${RAWYA_RELEASE_OUTPUT_DIR:-${artifact_dir}/release-${tag}}"
if [[ -e "$release_dir" ]]; then
  echo "Release output already exists; refusing to overwrite: ${release_dir}" >&2
  exit 1
fi

cleanup() {
  if [[ -n "${temporary_dir:-}" && -d "$temporary_dir" ]]; then
    rm -rf "$temporary_dir"
  fi
}
trap cleanup EXIT

temporary_dir="$(mktemp -d "${artifact_dir}/.release-preparation.XXXXXX")"
prepared_dir="${temporary_dir}/prepared"
appcast_source_dir="${temporary_dir}/appcast-source"
dmg_source_dir="${temporary_dir}/dmg-source"
mkdir -p "$prepared_dir" "$appcast_source_dir" "$dmg_source_dir"

zip_name="Rawya-${version}-${build_number}.zip"
dmg_name="Rawya-${version}-${build_number}.dmg"
source_name="Rawya-${version}-${build_number}-source.tar.gz"
cp "$source_zip" "${prepared_dir}/${zip_name}"
cp "$release_notes" "${prepared_dir}/release-notes.md"
cp "${prepared_dir}/${zip_name}" "${appcast_source_dir}/${zip_name}"
cp "$release_notes" "${appcast_source_dir}/Rawya-${version}-${build_number}.md"

ditto "$app_path" "${dmg_source_dir}/Rawya.app"
ln -s /Applications "${dmg_source_dir}/Applications"
hdiutil create \
  -quiet \
  -volname "Rawya ${version}" \
  -srcfolder "$dmg_source_dir" \
  -format UDZO \
  -ov \
  "${prepared_dir}/${dmg_name}"
hdiutil verify "${prepared_dir}/${dmg_name}"

git -C "$repo_root" archive \
  --format=tar.gz \
  --prefix="client-macos-${tag}/" \
  --output="${prepared_dir}/${source_name}" \
  "$tag"

"${sparkle_bin_dir}/generate_appcast" \
  --account "$sparkle_account" \
  --download-url-prefix "https://github.com/rawya-ai-player/client-macos/releases/download/${tag}/" \
  --link "https://rawya.app" \
  --maximum-versions 1 \
  --maximum-deltas 0 \
  --embed-release-notes \
  --disable-signing-warning \
  -o "${prepared_dir}/appcast.xml" \
  "$appcast_source_dir"
archive_signature="$(xmllint --xpath \
  "string((//item/enclosure)[1]/@*[local-name()='edSignature'])" \
  "${prepared_dir}/appcast.xml")"
"${sparkle_bin_dir}/sign_update" \
  --account "$sparkle_account" \
  --verify \
  "${appcast_source_dir}/${zip_name}" \
  "$archive_signature"
"${sparkle_bin_dir}/sign_update" \
  --account "$sparkle_account" \
  --disable-signing-warning \
  "${prepared_dir}/appcast.xml"
"${sparkle_bin_dir}/sign_update" \
  --account "$sparkle_account" \
  --verify \
  "${prepared_dir}/appcast.xml"

cat > "${prepared_dir}/release-info.txt" <<EOF
version=${version}
build=${build_number}
tag=${tag}
revision=${revision}
channel=stable
zip=${zip_name}
dmg=${dmg_name}
source=${source_name}
notes=release-notes.md
appcast=appcast.xml
sparkle_public_key=${public_key}
created_at=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
EOF

(
  cd "$prepared_dir"
  shasum -a 256 "$zip_name" "$dmg_name" "$source_name" release-notes.md appcast.xml > SHA256SUMS
)

"${repo_root}/scripts/validate_update_release.sh" \
  "$prepared_dir" \
  --require-macos-verification

mv "$prepared_dir" "$release_dir"
temporary_dir=""

echo "Prepared Rawya ${version} (${build_number}) release: ${release_dir}"
