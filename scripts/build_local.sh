#!/bin/bash

set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
build_home="${RAWYA_LOCAL_BUILD_HOME:-${HOME}/Library/Developer/Rawya}"
cache_root="${build_home}/BuildCache"
archive_root="${build_home}/Builds"
configuration="Debug"
derived_data="${cache_root}/DerivedData"
source_packages="${cache_root}/SourcePackages"
app_name="Rawya Dev"
expected_bundle_id="app.rawya.player.dev"
product_path="${derived_data}/Build/Products/${configuration}/${app_name}.app"
installed_app="/Applications/${app_name}.app"

mkdir -p "$cache_root" "$archive_root"

build_number="$("${repo_root}/scripts/next_build_number.sh")"

branch="$(git -C "$repo_root" branch --show-current)"
revision="$(git -C "$repo_root" rev-parse --short=12 HEAD)"
timestamp="$(date '+%Y%m%d-%H%M%S')"
archive_name="${timestamp}-${revision}"
archive_path="${archive_root}/${archive_name}"
suffix=2
while [[ -e "$archive_path" ]]; do
  archive_path="${archive_root}/${archive_name}-${suffix}"
  suffix=$((suffix + 1))
done

echo "Building Rawya locally (${configuration}, build ${build_number}, branch ${branch})"
DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer" \
  xcodebuild -quiet \
  -project "${repo_root}/iina.xcodeproj" \
  -scheme iina \
  -configuration "$configuration" \
  -clonedSourcePackagesDirPath "$source_packages" \
  -derivedDataPath "$derived_data" \
  CURRENT_PROJECT_VERSION="$build_number" \
  CODE_SIGNING_ALLOWED=NO \
  build

if [[ ! -d "$product_path" ]]; then
  echo "Build succeeded but ${app_name}.app was not found at ${product_path}" >&2
  exit 1
fi

product_bundle_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "${product_path}/Contents/Info.plist")"
if [[ "$product_bundle_id" != "$expected_bundle_id" ]]; then
  echo "Refusing to install local build with unexpected bundle ID: ${product_bundle_id}" >&2
  exit 1
fi
product_build_number="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "${product_path}/Contents/Info.plist")"
if [[ "$product_build_number" != "$build_number" ]]; then
  echo "Refusing to install local build with unexpected build number: ${product_build_number}" >&2
  exit 1
fi

codesign --force --deep --sign - "$product_path"
codesign --verify --deep --strict "$product_path"

archive_staging_path="$(mktemp -d "${archive_root}/.staging.XXXXXX")"
install_staging_dir=""
install_backup_path=""
cleanup_staging() {
  if [[ -n "${archive_staging_path:-}" && -d "$archive_staging_path" ]]; then
    /usr/bin/trash "$archive_staging_path"
  fi
  if [[ -n "${install_staging_dir:-}" && -d "$install_staging_dir" ]]; then
    /usr/bin/trash "$install_staging_dir"
  fi
  if [[ -n "${install_backup_path:-}" && -e "$install_backup_path" ]]; then
    if [[ ! -e "$installed_app" ]]; then
      mv "$install_backup_path" "$installed_app"
    else
      /usr/bin/trash "$install_backup_path"
    fi
  fi
}
trap cleanup_staging EXIT

ditto "$product_path" "${archive_staging_path}/${app_name}.app"
{
  echo "built_at=$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  echo "branch=${branch}"
  echo "revision=${revision}"
  echo "configuration=${configuration}"
  echo "build=${build_number}"
} > "${archive_staging_path}/build-info.txt"

mv "$archive_staging_path" "$archive_path"
archive_staging_path=""
ln -sfn "$archive_path" "${archive_root}/latest"

shopt -s nullglob
archives=("${archive_root}"/20[0-9][0-9][0-1][0-9][0-3][0-9]-[0-2][0-9][0-5][0-9][0-5][0-9]-*)
if (( ${#archives[@]} > 1 )); then
  remove_count=$((${#archives[@]} - 1))
  for ((index = 0; index < remove_count; index++)); do
    candidate="${archives[$index]}"
    candidate_parent="$(dirname "$candidate")"
    candidate_name="$(basename "$candidate")"
    if [[ "$candidate_parent" != "$archive_root" || ! "$candidate_name" =~ ^20[0-9]{6}-[0-9]{6}-[0-9a-f]{7,12}(-[0-9]+)?$ ]]; then
      echo "Refusing to remove unexpected archive path: ${candidate}" >&2
      exit 1
    fi
    echo "Moving old local build to Trash: ${candidate_name}"
    /usr/bin/trash "$candidate"
  done
fi

install_staging_dir="$(mktemp -d "/Applications/.RawyaDev.install.XXXXXX")"
ditto "$product_path" "${install_staging_dir}/${app_name}.app"
codesign --verify --deep --strict "${install_staging_dir}/${app_name}.app"

running_pids="$(pgrep -f '^/Applications/Rawya Dev\.app/Contents/MacOS/Rawya Dev( |$)' || true)"
if [[ -n "$running_pids" ]]; then
  echo "Stopping the installed ${app_name} before replacement"
  while IFS= read -r pid; do
    [[ -n "$pid" ]] && kill "$pid" 2>/dev/null || true
  done <<< "$running_pids"
  for _ in {1..50}; do
    if ! pgrep -f '^/Applications/Rawya Dev\.app/Contents/MacOS/Rawya Dev( |$)' >/dev/null; then
      break
    fi
    sleep 0.1
  done
  if pgrep -f '^/Applications/Rawya Dev\.app/Contents/MacOS/Rawya Dev( |$)' >/dev/null; then
    echo "Rawya is still running; refusing to replace the installed app" >&2
    exit 1
  fi
fi

if [[ -e "$installed_app" ]]; then
  install_backup_path="/Applications/.RawyaDev.previous.${timestamp}.$$"
  mv "$installed_app" "$install_backup_path"
fi
mv "${install_staging_dir}/${app_name}.app" "$installed_app"
rmdir "$install_staging_dir"
install_staging_dir=""
if ! codesign --verify --deep --strict "$installed_app"; then
  /usr/bin/trash "$installed_app"
  if [[ -n "$install_backup_path" && -e "$install_backup_path" ]]; then
    mv "$install_backup_path" "$installed_app"
    install_backup_path=""
  fi
  echo "Installed app verification failed; restored the previous ${app_name}.app" >&2
  exit 1
fi
installed_bundle_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "${installed_app}/Contents/Info.plist")"
if [[ "$installed_bundle_id" != "$expected_bundle_id" ]]; then
  /usr/bin/trash "$installed_app"
  if [[ -n "$install_backup_path" && -e "$install_backup_path" ]]; then
    mv "$install_backup_path" "$installed_app"
    install_backup_path=""
  fi
  echo "Installed app has unexpected bundle ID; restored the previous ${app_name}.app" >&2
  exit 1
fi
installed_build_number="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "${installed_app}/Contents/Info.plist")"
if [[ "$installed_build_number" != "$build_number" ]]; then
  /usr/bin/trash "$installed_app"
  if [[ -n "$install_backup_path" && -e "$install_backup_path" ]]; then
    mv "$install_backup_path" "$installed_app"
    install_backup_path=""
  fi
  echo "Installed app has unexpected build number; restored the previous ${app_name}.app" >&2
  exit 1
fi
if [[ -n "$install_backup_path" && -e "$install_backup_path" ]]; then
  /usr/bin/trash "$install_backup_path"
fi
install_backup_path=""

echo "Local build archived at: ${archive_path}/${app_name}.app"
echo "Rawya build ${build_number} installed at: ${installed_app}"
