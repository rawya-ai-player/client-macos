#!/bin/bash

set -euo pipefail

usage() {
  echo "Usage: $0 Rawya-YYYYMMDD-HHMMSS-COMMIT" >&2
}

if (( $# != 1 )); then
  usage
  exit 2
fi

keep_id="$1"
build_home="${RAWYA_DISTRIBUTION_HOME:-${HOME}/Library/Developer/Rawya/Distribution}"

if [[ ! "$keep_id" =~ ^Rawya-[0-9]{8}-[0-9]{6}-[0-9a-f]{12}$ ]]; then
  echo "Invalid Rawya distribution build ID: ${keep_id}" >&2
  exit 1
fi

keep_artifact="${build_home}/Artifacts/${keep_id}"
if [[ ! -d "$keep_artifact" ]]; then
  echo "Current artifact directory not found: ${keep_artifact}" >&2
  exit 1
fi

for bucket in Archives Artifacts Exports; do
  bucket_path="${build_home}/${bucket}"
  [[ -d "$bucket_path" ]] || continue

  while IFS= read -r -d '' candidate; do
    candidate_parent="$(dirname "$candidate")"
    candidate_name="$(basename "$candidate")"
    candidate_id="${candidate_name%.xcarchive}"

    if [[ "$candidate_parent" != "$bucket_path" ||
        ! "$candidate_id" =~ ^Rawya-[0-9]{8}-[0-9]{6}-[0-9a-f]{12}$ ]]; then
      echo "Refusing to remove unexpected distribution path: ${candidate}" >&2
      exit 1
    fi

    if [[ "$bucket" != "Exports" && "$candidate_id" == "$keep_id" ]]; then
      continue
    fi

    echo "Moving obsolete distribution output to Trash: ${candidate}"
    /usr/bin/trash "$candidate"
  done < <(find "$bucket_path" -mindepth 1 -maxdepth 1 -name 'Rawya-*' -print0)
done

echo "Kept latest Rawya distribution build: ${keep_id}"
