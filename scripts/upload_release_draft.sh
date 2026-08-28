#!/bin/bash

set -euo pipefail

usage() {
  echo "Usage: $0 /path/to/prepared-release" >&2
}

if (( $# != 1 )); then
  usage
  exit 2
fi

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
release_dir="${1%/}"
info_path="${release_dir}/release-info.txt"
repository="rawya-ai-player/client-macos"

if [[ "${RAWYA_CONFIRM_GITHUB_DRAFT:-}" != "CREATE_RAWYA_DRAFT" ]]; then
  echo "Creating a GitHub draft release requires explicit confirmation." >&2
  echo "Set RAWYA_CONFIRM_GITHUB_DRAFT=CREATE_RAWYA_DRAFT for an approved upload." >&2
  exit 1
fi

"${repo_root}/scripts/validate_update_release.sh" \
  "$release_dir" \
  --require-macos-verification

read_info() {
  local key="$1"
  awk -F= -v key="$key" '$1 == key { sub(/^[^=]*=/, ""); print; found = 1; exit } END { exit !found }' "$info_path"
}

version="$(read_info version)"
build_number="$(read_info build)"
tag="$(read_info tag)"
zip_name="$(read_info zip)"
dmg_name="$(read_info dmg)"
source_name="$(read_info source)"

if [[ "$(git -C "$repo_root" branch --show-current)" != "main" ||
      -n "$(git -C "$repo_root" status --porcelain)" ]]; then
  echo "GitHub release drafts require a clean main worktree." >&2
  exit 1
fi
if ! gh auth status >/dev/null 2>&1; then
  echo "GitHub CLI is not authenticated." >&2
  exit 1
fi
if gh release view "$tag" --repo "$repository" >/dev/null 2>&1; then
  echo "GitHub release already exists: ${tag}" >&2
  exit 1
fi

local_tag_revision="$(git -C "$repo_root" rev-parse "refs/tags/${tag}^{commit}")"
remote_tag_revision="$(git -C "$repo_root" ls-remote origin "refs/tags/${tag}^{}" | awk 'NR == 1 { print $1 }')"
if [[ -z "$remote_tag_revision" ]]; then
  remote_tag_revision="$(git -C "$repo_root" ls-remote origin "refs/tags/${tag}" | awk 'NR == 1 { print $1 }')"
fi
if [[ "$local_tag_revision" != "$remote_tag_revision" ]]; then
  echo "Remote tag ${tag} is missing or does not match the local annotated tag." >&2
  exit 1
fi

gh release create "$tag" \
  --repo "$repository" \
  --draft \
  --verify-tag \
  --title "Rawya ${version} (${build_number})" \
  --notes-file "${release_dir}/release-notes.md" \
  "${release_dir}/${zip_name}#Automatic update package - no manual download" \
  "${release_dir}/${dmg_name}#macOS installer - download this" \
  "${release_dir}/${source_name}#Corresponding source" \
  "${release_dir}/release-notes.md#Release notes" \
  "${release_dir}/appcast.xml#Automatic update metadata - no manual download" \
  "${release_dir}/SHA256SUMS#SHA-256 checksums" \
  "${release_dir}/release-info.txt#Release manifest"

is_draft="$(gh release view "$tag" --repo "$repository" --json isDraft --jq .isDraft)"
if [[ "$is_draft" != "true" ]]; then
  echo "Release upload completed but the release is not a draft." >&2
  exit 1
fi

echo "Created GitHub draft release ${tag}."
echo "Dispatch publish-release.yml and approve the macos-release environment to publish it."
