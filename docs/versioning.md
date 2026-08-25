# Versioning and build numbers

Rawya versions are independent from IINA versions. Rawya follows semantic
versioning for user-visible releases and uses a separate monotonically
increasing build number for update comparison and release traceability.

## Version fields

- `MARKETING_VERSION` is the user-visible `MAJOR.MINOR.PATCH` version. The
  first Rawya release is `1.0.0`.
- `CURRENT_PROJECT_VERSION` is the numeric build number. Rawya starts at
  `1001` and increments it globally for every distributed build.
- The main app and all bundled extensions must use the same marketing version
  and build number.
- IINA's release tag and base commit are upstream provenance only. They do not
  determine Rawya's product version.

The canonical values live in `Configs/Deployment.xcconfig`.

## Semantic versioning

Increment the Rawya marketing version according to user-visible impact:

- `MAJOR`: incompatible product, data, plugin, automation, entitlement, or
  distribution changes that require explicit user migration or define a new
  product generation.
- `MINOR`: backward-compatible user-facing features or substantial workflow
  improvements.
- `PATCH`: backward-compatible bug fixes, security fixes, performance and
  compatibility improvements, localization changes, and maintenance work.

An IINA upgrade does not automatically produce the same Rawya version. Classify
the resulting Rawya release by its actual user impact. Record the IINA tag and
base commit in the upstream strategy and release notes.

## Build numbers

- Start at `1001`.
- Use a plain integer with no leading zeroes.
- Increment for every build distributed to testers or users, including beta,
  release candidate, and final builds.
- Never reset the build number when the marketing version changes.
- Never reuse a build number after an artifact has been distributed, even if
  that artifact is later withdrawn or the release fails.
- Local developer and local signing-validation builds may share the configured
  build number as long as they never leave the build machine. Every artifact
  distributed to testers or users must have a unique higher build number.
- Continue from `9999` to `10000`; four digits are the starting convention, not
  a maximum.

Sparkle must publish the build number as `sparkle:version` and the marketing
version as `sparkle:shortVersionString`.

## Pre-releases

Apple bundle marketing versions remain numeric. A beta or release candidate
for `1.1.0` therefore still uses `MARKETING_VERSION = 1.1.0`; the channel and
sequence are expressed by the Git tag and release metadata.

- Beta tag: `rawya-v1.1.0-beta.1`
- Release candidate tag: `rawya-v1.1.0-rc.1`
- Final tag: `rawya-v1.1.0`

Each pre-release consumes its own build number. Until Rawya has a separately
validated Sparkle pre-release channel, beta and release-candidate artifacts
must not be added to the stable appcast.

## Git tags and releases

Rawya tags use the `rawya-v` prefix because the repository retains IINA's
historical `vX.Y.Z` tags for upstream traceability.

- Create annotated tags only from an approved commit on `main`.
- A final tag must exactly match `rawya-v<MARKETING_VERSION>`.
- A pre-release tag must match the formats documented above.
- Never move, delete, or reuse a published Rawya tag.
- Use the release title `Rawya <MARKETING_VERSION> (<BUILD_NUMBER>)`.
- The appcast, archive, release notes, and generated app bundle must agree on
  the same marketing version and build number.

## Examples

| Distribution | Marketing version | Build | Git tag |
| --- | --- | ---: | --- |
| First final release | `1.0.0` | `1001` | `rawya-v1.0.0` |
| First `1.0.1` beta | `1.0.1` | `1002` | `rawya-v1.0.1-beta.1` |
| Final `1.0.1` | `1.0.1` | `1003` | `rawya-v1.0.1` |
| Feature release | `1.1.0` | `1004` | `rawya-v1.1.0` |

If pre-release builds are not distributed, they do not consume build numbers;
the next distributed artifact uses the next available number.

## Release checklist

Before producing a distributable artifact:

1. Select the semantic version from the user-visible change scope.
2. Assign a new build number greater than every previously distributed build.
3. Update `Configs/Deployment.xcconfig` and verify all bundled targets resolve
   to the same values.
4. Record the current IINA base tag and commit without copying that version into
   Rawya's marketing version.
5. Build, sign, notarize, staple, and test the exact release commit.
6. Create the annotated `rawya-v*` tag only after approval.
7. Verify the app bundle, archive, release title, and appcast metadata before
   publishing the release.
