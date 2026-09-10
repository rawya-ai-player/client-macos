#!/bin/bash

set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
state_home="${RAWYA_BUILD_NUMBER_HOME:-${HOME}/Library/Developer/Rawya/BuildNumber}"
applications_dir="${RAWYA_APPLICATIONS_DIR:-/Applications}"
state_file="${state_home}/current"
fingerprint_file="${state_home}/fingerprint"
lock_file="${state_home}/.lock"
lock_acquired=0
temporary_file=""
fingerprint_index_dir=""

mkdir -p "$state_home"

cleanup() {
  if [[ -n "$temporary_file" && -e "$temporary_file" ]]; then
    /usr/bin/trash "$temporary_file"
  fi
  if [[ -n "$fingerprint_index_dir" && -d "$fingerprint_index_dir" ]]; then
    /usr/bin/trash "$fingerprint_index_dir"
  fi
  if (( lock_acquired )); then
    rm -f "$lock_file"
  fi
}
trap cleanup EXIT

for _ in {1..200}; do
  if /usr/bin/shlock -f "$lock_file" -p $$; then
    lock_acquired=1
    break
  fi
  sleep 0.05
done

if (( ! lock_acquired )); then
  echo "Timed out waiting for the Rawya build-number lock: ${lock_file}" >&2
  exit 1
fi

force_new="${RAWYA_FORCE_NEW_BUILD_NUMBER:-0}"
if [[ "$force_new" != "0" && "$force_new" != "1" ]]; then
  echo "RAWYA_FORCE_NEW_BUILD_NUMBER must be 0 or 1" >&2
  exit 1
fi

# Build a temporary Git index from the actual working tree. Its tree hash
# covers committed, staged, modified, deleted, and non-ignored untracked files
# without changing the developer's real index.
fingerprint_index_dir="$(mktemp -d "${state_home}/.fingerprint-index.XXXXXX")"
temporary_index="${fingerprint_index_dir}/index"
GIT_INDEX_FILE="$temporary_index" git -C "$repo_root" read-tree HEAD
GIT_INDEX_FILE="$temporary_index" git -C "$repo_root" add -A -- .
source_fingerprint="$(GIT_INDEX_FILE="$temporary_index" git -C "$repo_root" write-tree)"
/usr/bin/trash "$fingerprint_index_dir"
fingerprint_index_dir=""

baseline="$(awk -F ' *= *' '/^CURRENT_PROJECT_VERSION *= *[0-9]+$/ { print $2; exit }' \
  "${repo_root}/Configs/Deployment.xcconfig")"
if [[ ! "$baseline" =~ ^[0-9]+$ ]]; then
  echo "Unable to read the build-number baseline from Configs/Deployment.xcconfig" >&2
  exit 1
fi

current="$baseline"
persisted_build_number=""
consider_build_number() {
  local candidate="$1"
  local source="$2"
  if [[ ! "$candidate" =~ ^[0-9]+$ ]]; then
    echo "Invalid build number in ${source}: ${candidate}" >&2
    exit 1
  fi
  if (( candidate > current )); then
    current="$candidate"
  fi
}

if [[ -f "$state_file" ]]; then
  persisted_build_number="$(tr -d '[:space:]' < "$state_file")"
  consider_build_number "$persisted_build_number" "$state_file"
fi

for app_name in "Rawya Dev" "Rawya"; do
  info_plist="${applications_dir}/${app_name}.app/Contents/Info.plist"
  if [[ -f "$info_plist" ]]; then
    installed_build="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$info_plist")"
    consider_build_number "$installed_build" "$info_plist"
  fi
done

persisted_fingerprint=""
if [[ -f "$fingerprint_file" ]]; then
  persisted_fingerprint="$(tr -d '[:space:]' < "$fingerprint_file")"
  if [[ ! "$persisted_fingerprint" =~ ^[0-9a-f]{40}$ ]]; then
    echo "Invalid source fingerprint in ${fingerprint_file}: ${persisted_fingerprint}" >&2
    exit 1
  fi
fi

if [[ "$force_new" == "0"
      && "$source_fingerprint" == "$persisted_fingerprint"
      && -n "$persisted_build_number"
      && "$persisted_build_number" == "$current" ]]; then
  echo "Reusing Rawya build ${current} for unchanged source ${source_fingerprint}" >&2
  printf '%s\n' "$current"
  exit 0
fi

if (( current >= 2147483647 )); then
  echo "Rawya build number has reached the supported integer limit" >&2
  exit 1
fi

next=$((current + 1))
temporary_file="$(mktemp "${state_home}/.current.XXXXXX")"
printf '%s\n' "$next" > "$temporary_file"
mv "$temporary_file" "$state_file"
temporary_file=""

temporary_file="$(mktemp "${state_home}/.fingerprint.XXXXXX")"
printf '%s\n' "$source_fingerprint" > "$temporary_file"
mv "$temporary_file" "$fingerprint_file"
temporary_file=""

echo "Allocated Rawya build ${next} for source ${source_fingerprint}" >&2
printf '%s\n' "$next"
