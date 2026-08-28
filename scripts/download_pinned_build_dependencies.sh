#!/bin/bash

set -euo pipefail

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "Pinned Rawya build dependencies require macOS." >&2
  exit 1
fi

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
version="v1.4.4"
asset_name="IINA.${version}.dmg"
asset_url="https://github.com/iina/iina/releases/download/${version}/${asset_name}"
expected_sha256="dd0fc0bd4b37fb57a1c8d30d6e3201b3a64bafd29959fe56953964613237beb1"
manifest="${repo_root}/Configs/IINA-v1.4.4-build-libraries.txt"
temporary_dir=""
mount_dir=""
mounted=0

cleanup() {
  if (( mounted )); then
    hdiutil detach "$mount_dir" -quiet || true
  fi
  if [[ -n "${temporary_dir:-}" && -d "$temporary_dir" ]]; then
    rm -rf "$temporary_dir"
  fi
}
trap cleanup EXIT

if [[ ! -f "$manifest" ]]; then
  echo "Pinned dependency manifest not found: ${manifest}" >&2
  exit 1
fi

temporary_dir="$(mktemp -d "${TMPDIR:-/tmp}/rawya-pinned-dependencies.XXXXXX")"
mount_dir="${temporary_dir}/mount"
dmg_path="${temporary_dir}/${asset_name}"
mkdir -p "$mount_dir"

curl --fail --location --retry 3 --show-error \
  --output "$dmg_path" \
  "$asset_url"

actual_sha256="$(shasum -a 256 "$dmg_path" | awk '{ print $1 }')"
if [[ "$actual_sha256" != "$expected_sha256" ]]; then
  echo "Pinned IINA dependency image failed SHA-256 verification." >&2
  exit 1
fi

hdiutil attach \
  -nobrowse \
  -readonly \
  -mountpoint "$mount_dir" \
  "$dmg_path" >/dev/null
mounted=1

source_app="$(find "$mount_dir" -maxdepth 2 -type d -name IINA.app -print -quit)"
source_frameworks="${source_app}/Contents/Frameworks"
source_youtube_dl="${source_app}/Contents/MacOS/youtube-dl"
if [[ -z "$source_app" || ! -d "$source_frameworks" || ! -f "$source_youtube_dl" ]]; then
  echo "Pinned IINA image does not contain the expected application layout." >&2
  exit 1
fi

library_dir="${repo_root}/deps/lib"
executable_dir="${repo_root}/deps/executable"
mkdir -p "$library_dir" "$executable_dir"

while IFS= read -r library_name; do
  [[ -n "$library_name" ]] || continue
  source_library="${source_frameworks}/${library_name}"
  if [[ ! -e "$source_library" ]]; then
    echo "Pinned IINA image is missing ${library_name}." >&2
    exit 1
  fi
  ditto "$source_library" "${library_dir}/${library_name}"
done < "$manifest"

ditto "$source_youtube_dl" "${executable_dir}/youtube-dl"
chmod +x "${executable_dir}/youtube-dl"

echo "Installed checksum-pinned IINA ${version} build dependencies."
