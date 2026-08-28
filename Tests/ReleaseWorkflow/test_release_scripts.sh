#!/bin/bash

set -euo pipefail

repo_root="$(cd "$(dirname "$0")/../.." && pwd)"
fixture_dir="$(mktemp -d "${TMPDIR:-/tmp}/rawya-release-test.XXXXXX")"
trap 'rm -rf "$fixture_dir"' EXIT

bash -n "${repo_root}/scripts/download_pinned_build_dependencies.sh"
manifest="${repo_root}/Configs/IINA-v1.4.4-build-libraries.txt"
manifest_entries="$(wc -l < "$manifest" | tr -d ' ')"
unique_manifest_entries="$(sort -u "$manifest" | wc -l | tr -d ' ')"
if [[ "$unique_manifest_entries" != "$manifest_entries" ]]; then
  echo "Pinned build dependency manifest contains duplicate entries." >&2
  exit 1
fi

version="9.8.7"
build="9876"
tag="rawya-v${version}"
zip_name="Rawya-${version}-${build}.zip"
dmg_name="Rawya-${version}-${build}.dmg"
source_name="Rawya-${version}-${build}-source.tar.gz"

printf 'zip fixture' > "${fixture_dir}/${zip_name}"
printf 'dmg fixture' > "${fixture_dir}/${dmg_name}"
printf 'source fixture' > "${fixture_dir}/${source_name}"
printf '# Release notes\n' > "${fixture_dir}/release-notes.md"
zip_length="$(stat -f '%z' "${fixture_dir}/${zip_name}")"

write_fixture() {
  local version_format="${1:-attribute}"

  if [[ "$version_format" == "attribute" ]]; then
    cat > "${fixture_dir}/appcast.xml" <<EOF
<?xml version="1.0" encoding="utf-8"?>
<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" version="2.0">
  <channel>
    <item>
      <title>Rawya ${version}</title>
      <enclosure
        url="https://github.com/rawya-ai-player/client-macos/releases/download/${tag}/${zip_name}"
        length="${zip_length}"
        type="application/octet-stream"
        sparkle:version="${build}"
        sparkle:shortVersionString="${version}"
        sparkle:edSignature="fixture-signature"/>
    </item>
  </channel>
</rss>
<!-- sparkle-signatures:
edSignature: fixture-feed-signature
length: 1
-->
EOF
  elif [[ "$version_format" == "element" ]]; then
    cat > "${fixture_dir}/appcast.xml" <<EOF
<?xml version="1.0" encoding="utf-8"?>
<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" version="2.0">
  <channel>
    <item>
      <title>Rawya ${version}</title>
      <sparkle:version>${build}</sparkle:version>
      <sparkle:shortVersionString>${version}</sparkle:shortVersionString>
      <enclosure
        url="https://github.com/rawya-ai-player/client-macos/releases/download/${tag}/${zip_name}"
        length="${zip_length}"
        type="application/octet-stream"
        sparkle:edSignature="fixture-signature"/>
    </item>
  </channel>
</rss>
<!-- sparkle-signatures:
edSignature: fixture-feed-signature
length: 1
-->
EOF
  else
    echo "Unknown appcast version format: ${version_format}" >&2
    exit 1
  fi

  cat > "${fixture_dir}/release-info.txt" <<EOF
version=${version}
build=${build}
tag=${tag}
revision=0123456789abcdef0123456789abcdef01234567
channel=stable
zip=${zip_name}
dmg=${dmg_name}
source=${source_name}
notes=release-notes.md
appcast=appcast.xml
sparkle_public_key=AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=
created_at=2026-08-28T00:00:00Z
EOF

  (
    cd "$fixture_dir"
    shasum -a 256 "$zip_name" "$dmg_name" "$source_name" release-notes.md appcast.xml > SHA256SUMS
  )
}

write_fixture
"${repo_root}/scripts/validate_update_release.sh" "$fixture_dir"

tag="rawya-v${version}-build${build}"
write_fixture
"${repo_root}/scripts/validate_update_release.sh" "$fixture_dir"

tag="rawya-v${version}"
write_fixture element
"${repo_root}/scripts/validate_update_release.sh" "$fixture_dir"
