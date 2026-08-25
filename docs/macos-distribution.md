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

## Notarize and staple

Pass the signed app produced by the build script:

```bash
RAWYA_CONFIRM_NOTARIZATION=NOTARIZE_RAWYA \
  ./scripts/notarize_distribution.sh \
  "$HOME/Library/Developer/Rawya/Distribution/Artifacts/BUILD/Rawya.app"
```

The script submits a ZIP with `notarytool`, waits for the result, stores the
response and failure log next to the artifact, staples the accepted ticket,
checks Gatekeeper with `spctl`, and creates a final notarized ZIP.

Submitting a build for notarization is an external Apple operation. Do it only
for an approved release candidate or an explicitly approved validation build.
The explicit environment value prevents an accidental submission.

## Continuous integration

The current GitHub Actions build intentionally uses
`CODE_SIGNING_ALLOWED=NO`. Its artifact is only a compile-check result and must
never be uploaded as a Rawya release. Formal signing and notarization remain on
a trusted Mac until a separate release workflow has encrypted certificate,
notarization, and Sparkle secrets plus protected-environment approval.

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
