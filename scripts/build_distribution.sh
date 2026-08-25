#!/bin/bash

set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
developer_dir="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
team_id="${RAWYA_DEVELOPMENT_TEAM:-W684N2R45F}"
signing_identity="${RAWYA_CODE_SIGN_IDENTITY:-Developer ID Application: Shanghai Yunshang Wanwei Technology Co., Ltd. (W684N2R45F)}"
build_home="${RAWYA_DISTRIBUTION_HOME:-${HOME}/Library/Developer/Rawya/Distribution}"
source_packages="${RAWYA_SOURCE_PACKAGES:-${HOME}/Library/Developer/Rawya/BuildCache/SourcePackages}"
timestamp="$(date '+%Y%m%d-%H%M%S')"
branch="$(git -C "$repo_root" branch --show-current)"
revision="$(git -C "$repo_root" rev-parse --short=12 HEAD)"
archive_path="${build_home}/Archives/Rawya-${timestamp}-${revision}.xcarchive"
export_path="${build_home}/Exports/Rawya-${timestamp}-${revision}"
artifact_dir="${build_home}/Artifacts/Rawya-${timestamp}-${revision}"

if [[ ! -d "$developer_dir" ]]; then
  echo "Xcode developer directory not found: ${developer_dir}" >&2
  exit 1
fi

if ! security find-identity -v -p codesigning | grep -Fq "\"${signing_identity}\""; then
  echo "Signing identity and private key not found: ${signing_identity}" >&2
  exit 1
fi

if [[ "$branch" != "main" && "${RAWYA_ALLOW_NON_MAIN:-0}" != "1" ]]; then
  echo "Distribution builds must come from main; current branch is ${branch}." >&2
  echo "Set RAWYA_ALLOW_NON_MAIN=1 only for a local signing validation build." >&2
  exit 1
fi

if [[ -n "$(git -C "$repo_root" status --porcelain)" && "${RAWYA_ALLOW_DIRTY:-0}" != "1" ]]; then
  echo "Distribution builds require a clean worktree." >&2
  echo "Set RAWYA_ALLOW_DIRTY=1 only for a local signing validation build." >&2
  exit 1
fi

mkdir -p "$(dirname "$archive_path")" "$(dirname "$export_path")" "$artifact_dir"

echo "Archiving Rawya with Developer ID (${branch} @ ${revision})"
DEVELOPER_DIR="$developer_dir" \
  xcodebuild -quiet \
  -project "${repo_root}/iina.xcodeproj" \
  -scheme iina \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -archivePath "$archive_path" \
  -clonedSourcePackagesDirPath "$source_packages" \
  DEVELOPMENT_TEAM="$team_id" \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY="$signing_identity" \
  OTHER_CODE_SIGN_FLAGS='--timestamp' \
  archive

echo "Exporting the archive for Developer ID distribution"
DEVELOPER_DIR="$developer_dir" \
  xcodebuild -quiet \
  -exportArchive \
  -archivePath "$archive_path" \
  -exportPath "$export_path" \
  -exportOptionsPlist "${repo_root}/Configs/DeveloperIDExportOptions.plist"

exported_app="${export_path}/Rawya.app"
if [[ ! -d "$exported_app" ]]; then
  echo "Export succeeded but Rawya.app was not found: ${exported_app}" >&2
  exit 1
fi

app_path="${artifact_dir}/Rawya.app"
ditto "$exported_app" "$app_path"

# Xcode exports the prebuilt yt-dlp executable with Developer ID but preserves
# its missing Hardened Runtime flag. Sign that executable explicitly, then seal
# the outer app again with its release entitlements.
youtube_dl_path="${app_path}/Contents/MacOS/youtube-dl"
if [[ ! -f "$youtube_dl_path" ]]; then
  echo "Bundled youtube-dl executable not found: ${youtube_dl_path}" >&2
  exit 1
fi
codesign --force \
  --options runtime \
  --timestamp \
  --sign "$signing_identity" \
  "$youtube_dl_path"
codesign --force \
  --options runtime \
  --timestamp \
  --entitlements "${repo_root}/iina/IINA.entitlements" \
  --sign "$signing_identity" \
  "$app_path"

"${repo_root}/scripts/verify_distribution.sh" "$app_path"

version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "${app_path}/Contents/Info.plist")"
build_number="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "${app_path}/Contents/Info.plist")"
submission_zip="${artifact_dir}/Rawya-${version}-${build_number}-signed.zip"
ditto -c -k --sequesterRsrc --keepParent "$app_path" "$submission_zip"

{
  echo "version=${version}"
  echo "build=${build_number}"
  echo "branch=${branch}"
  echo "revision=${revision}"
  echo "signed_at=$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  echo "team_id=${team_id}"
  echo "notarized=no"
} > "${artifact_dir}/distribution-info.txt"

echo "Signed app: ${app_path}"
echo "Notarization upload: ${submission_zip}"
echo "Archive: ${archive_path}"
echo "Export: ${export_path}"
