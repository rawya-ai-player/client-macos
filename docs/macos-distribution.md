# macOS distribution signing and notarization

Rawya is distributed outside the Mac App Store. Formal builds use Apple's
Developer ID signing and notarization flow. Local Debug builds remain ad-hoc
signed and are not distribution artifacts.

## Signing identity

- Team ID: `W684N2R45F`
- Certificate type: `Developer ID Application`
- Application bundle ID: `app.rawya.player`
- Safari extension bundle ID: `app.rawya.player.OpenInIINA`

Never commit certificates, private keys, App Store Connect API keys, Apple
Account passwords, or Sparkle private keys to this repository.

## Application update behavior

Rawya uses Sparkle's stable update channel. The application checks the stable
appcast once per day by default. Users can disable scheduled checks, change the
interval, or invoke `Rawya > Check for Updates...` at any time. Automatic
download and installation is off by default and can be enabled explicitly in
General preferences. When enabled, Sparkle downloads a verified update in the
background and installs it when Rawya quits.

Both scheduled and manual checks use:

```text
https://github.com/rawya-ai-player/client-macos/releases/latest/download/appcast.xml
```

The latest stable GitHub Release must therefore contain a signed `appcast.xml`
and the exact ZIP referenced by its signed enclosure. Rawya requires both feed
validation and archive validation before extraction. Beta updates are
intentionally not offered until a separately hosted and validated channel
exists.

## One-time Sparkle key setup

The update signing key is stored in the login keychain under the `rawya`
account. Generate it only once:

```bash
SPARKLE_BIN="$HOME/Library/Developer/Rawya/BuildCache/SourcePackages/artifacts/sparkle/Sparkle/bin"
"$SPARKLE_BIN/generate_keys" --account rawya
```

`SUPublicEDKey` in `iina/Info.plist` must match the printed public key. Before
the first public release, export the private key to an encrypted, access-
controlled backup outside the repository:

```bash
"$SPARKLE_BIN/generate_keys" --account rawya -x /secure/backup/rawya-sparkle-private-key
```

Losing this key prevents existing installations from accepting future update
archives. The release preparation script refuses to continue when the
keychain key and application public key differ.

## One-time notarization credential setup

Store credentials in the login keychain under the profile name
`rawya-notary`. App Store Connect API keys are preferred for automation:

```bash
xcrun notarytool store-credentials rawya-notary \
  --key /secure/path/AuthKey_KEYID.p8 \
  --key-id KEYID \
  --issuer ISSUER_UUID
```

An Apple Account and app-specific password can also be stored interactively:

```bash
xcrun notarytool store-credentials rawya-notary \
  --apple-id "APPLE_ACCOUNT_EMAIL" \
  --team-id W684N2R45F
```

Do not pass a password in shell history. Let `notarytool` prompt for it.

## Build a signed archive

Formal builds must come from a clean `main` worktree:

```bash
./scripts/build_distribution.sh
```

The script creates an Xcode archive, exports it with Xcode's `developer-id`
method, and produces a Developer ID-signed `Rawya.app` plus a ZIP suitable for notarization under
`~/Library/Developer/Rawya/Distribution`. It verifies the main app, bundled
extension, nested Mach-O code, Hardened Runtime, secure timestamp, Team ID, and
bundle identifiers. The prebuilt `youtube-dl` executable is explicitly
re-signed with Hardened Runtime after export before the outer app is sealed
again.

For local signing-pipeline validation on an uncommitted development branch:

```bash
RAWYA_ALLOW_NON_MAIN=1 RAWYA_ALLOW_DIRTY=1 \
  ./scripts/build_distribution.sh
```

Validation artifacts must remain local. They do not consume a build number
until they are distributed to a tester or user.

## Artifact formats and retention

`Rawya.app` is the actual application bundle and is produced for every local or
distribution build. Use it for local installation and direct application
testing. Do not publish a bare `.app` because it is a directory bundle and can
lose metadata when transferred without an archive.

Create a DMG only for a release that people install manually from the Rawya
website or GitHub Releases. The DMG is a presentation and transport container;
it contains the already signed `Rawya.app` and normally an Applications folder
shortcut. It does not replace the app build.

Every stable release publishes a notarized ZIP with a Sparkle EdDSA signature
in the appcast. A public release therefore has both installation formats:

- `Rawya-<version>-<build>.dmg` for manual download and drag-to-Applications install.
- `Rawya-<version>-<build>.zip` for Sparkle automatic updates.

Local Debug builds only retain the most recent archived app. Distribution
builds retain the most recent successful notarized build set: its Xcode archive
for symbols, notarized app, final distribution archive, manifest, and
notarization response. Older build sets and transient Export/upload archives
are moved to Trash only after the new notarized artifact passes verification.

## Notarize and staple

Pass the signed app produced by the build script:

```bash
RAWYA_CONFIRM_NOTARIZATION=NOTARIZE_RAWYA \
  ./scripts/notarize_distribution.sh \
  "$HOME/Library/Developer/Rawya/Distribution/Artifacts/BUILD/Rawya.app"
```

The script submits a ZIP with `notarytool`, waits for the result, stores the
response and failure log next to the artifact, staples the accepted ticket,
checks Gatekeeper with `spctl`, creates a final notarized ZIP, and verifies the
app again after extracting that ZIP. Older builds are pruned only after this
final archive verification passes.

Submitting a build for notarization is an external Apple operation. Do it only
for an approved release candidate or an explicitly approved validation build.
The explicit environment value prevents an accidental submission.

## Prepare the update release

Create approved Markdown release notes, create an annotated
`rawya-v<MARKETING_VERSION>` tag on the exact `main` commit used for the first
build of a version, then prepare the release bundle. A later stable build with
the same marketing version uses `rawya-v<MARKETING_VERSION>-build<BUILD>` and
passes that tag through `RAWYA_RELEASE_TAG`:

```bash
./scripts/prepare_update_release.sh \
  "$HOME/Library/Developer/Rawya/Distribution/Artifacts/BUILD/Rawya.app" \
  /path/to/release-notes.md

RAWYA_RELEASE_TAG=rawya-v1.0.0-build1006 \
  ./scripts/prepare_update_release.sh \
  "$HOME/Library/Developer/Rawya/Distribution/Artifacts/BUILD/Rawya.app" \
  /path/to/release-notes.md
```

The script verifies the Developer ID signature, notarization, Git tag, source
revision, Sparkle key, archive signature, appcast metadata, DMG, checksums, and
corresponding-source archive. It produces a new `release-rawya-v*` directory
next to the notarized app and refuses to overwrite an existing directory.

## Upload and publish

Pushing the annotated tag, creating the GitHub draft, and publishing it are
separate external actions. After the tag has been approved and pushed, create
the draft with an explicit confirmation:

```bash
RAWYA_CONFIRM_GITHUB_DRAFT=CREATE_RAWYA_DRAFT \
  ./scripts/upload_release_draft.sh /path/to/release-rawya-v1.0.0
```

The script validates the complete bundle again, verifies the remote annotated
tag, and uploads all assets as an unpublished GitHub draft. It never publishes
the release.

Configure the GitHub environment named `macos-release` with required reviewers
before the first release. An approver can then run the `Publish macOS release`
workflow with the exact tag. The workflow downloads and validates the draft,
independently verifies the ZIP and appcast Ed25519 signatures using only the
public key from the tagged source, publishes it as the latest stable release,
and confirms that the public `appcast.xml` is byte-for-byte identical to the
approved asset.

## Continuous integration

The normal GitHub Actions build intentionally uses `CODE_SIGNING_ALLOWED=NO`.
Its artifact is only a compile-check result and must never be uploaded as a
Rawya release. Formal signing, notarization, and Sparkle signing remain on a
trusted Mac. The protected release workflow only validates and publishes an
already prepared GitHub draft, so Apple and Sparkle secrets never enter CI.

## Release gate

Before publishing a GitHub Release or updating the Sparkle appcast, confirm:

1. The release commit is approved, committed, and on `main`.
2. Version, build number, Git tag, app bundle, and release notes agree.
3. `verify_distribution.sh --require-notarization` passes.
4. The notarized archive launches on a clean Mac with Gatekeeper enabled.
5. The update archive has a valid Sparkle EdDSA signature.
6. The exact GPLv3 corresponding source is available with the binary release.

Apple Developer ID signing, Apple notarization, and Sparkle EdDSA signing are
independent checks. Passing one does not replace the others.

## References

- [Apple: Notarizing macOS software before distribution](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)
- [Apple: Developer ID certificates](https://developer.apple.com/help/account/certificates/create-developer-id-certificates/)
- [Sparkle: Code signing embedded helpers](https://sparkle-project.org/documentation/sandboxing/#code-signing)
- [Sparkle: Publishing an update](https://sparkle-project.org/documentation/publishing/)
