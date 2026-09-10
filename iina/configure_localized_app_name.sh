#!/bin/bash

set -euo pipefail

resources_dir="${TARGET_BUILD_DIR}/${UNLOCALIZED_RESOURCES_FOLDER_PATH}"

set_localized_name() {
  local locale="$1"
  local name="$2"
  local strings_file="${resources_dir}/${locale}.lproj/InfoPlist.strings"

  if [[ ! -f "$strings_file" ]]; then
    echo "Missing localized bundle metadata: ${strings_file}" >&2
    exit 1
  fi

  /usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName ${name}" "$strings_file"
  /usr/libexec/PlistBuddy -c "Set :CFBundleName ${name}" "$strings_file"
}

set_localized_name "zh-Hans" "${RAWYA_LOCALIZED_APP_NAME_ZH_HANS}"
set_localized_name "zh-Hant" "${RAWYA_LOCALIZED_APP_NAME_ZH_HANT}"
