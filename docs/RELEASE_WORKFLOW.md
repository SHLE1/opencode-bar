# Release Workflow Guide

This document describes the current release workflow for **UsageBar**.

> **Current Policy**
>
> - There is currently **no Apple signing certificate** available for this project.
> - Releases must publish **unsigned `.zip`** and **unsigned `.dmg`** artifacts only.
> - Releases must publish **`appcast.xml`** for Sparkle update checks.
> - `appcast.xml` must expose the ZIP archive as the Sparkle update enclosure.
> - The Sparkle enclosure must include an EdDSA signature generated from `SPARKLE_ED_PRIVATE_KEY`.
> - Every release must include **release notes**.
> - Every unsigned release must include a **Gatekeeper / `xattr` notice**.
> - Every release must also update the **`SHLE1/homebrew-tap`** cask to the same version.

## Prerequisites

- **Xcode Command Line Tools**
- **GitHub CLI (`gh`)** installed and authenticated
- Push access to `SHLE1/usage-bar`
- Push access to `SHLE1/homebrew-tap`
- `HOMEBREW_TAP_GITHUB_TOKEN` available for workflow-based releases
- `SPARKLE_ED_PRIVATE_KEY` available as a GitHub Actions secret.
  - This is the Sparkle EdDSA private key, not an Apple Developer certificate.
  - Its public key must match `SUPublicEDKey` in `UsageBar/UsageBar/Info.plist`.

If the matching private key is unavailable, generate a new Sparkle key pair, update `SUPublicEDKey`, and save the exported private key as the `SPARKLE_ED_PRIVATE_KEY` repository secret:

```bash
SPARKLE_BIN="/path/to/Sparkle/bin"
"$SPARKLE_BIN/generate_keys"
"$SPARKLE_BIN/generate_keys" -x sparkle-private-key.txt
```

Treat `sparkle-private-key.txt` as a secret and delete the local copy after storing it in GitHub Actions secrets.

## Release Outputs

Each release should publish:

- `UsageBar-v<VERSION>-unsigned.zip`
- `UsageBar-v<VERSION>-unsigned.dmg`
- `appcast.xml`
- `release-notes.html`

Both artifacts must be built as **universal binaries**:

- Main app binary: `arm64` + `x86_64`
- Embedded CLI binary: `arm64` + `x86_64`

## Recommended Workflow

## 1. Bump Version

Update these files to the new version:

- `UsageBar/UsageBar/Info.plist`
  - `CFBundleShortVersionString`
  - `CFBundleVersion`
- `README.md`
- `README.zh-CN.md`

Example:

```bash
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString 0.0.7" UsageBar/UsageBar/Info.plist
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion 0.0.7" UsageBar/UsageBar/Info.plist
```

## 2. Build Unsigned Release Archive

```bash
cd UsageBar
xcodebuild -project UsageBar.xcodeproj \
  -scheme UsageBar \
  -configuration Release \
  -destination "generic/platform=macOS" \
  -archivePath build/UsageBar.xcarchive \
  archive \
  ARCHS="arm64 x86_64" \
  ONLY_ACTIVE_ARCH=NO \
  CODE_SIGN_IDENTITY="-" \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO
```

## 3. Export App Bundle

```bash
mkdir -p build/export
cp -R "build/UsageBar.xcarchive/Products/Applications/UsageBar.app" build/export/
```

## 4. Verify Universal Binary Slices

```bash
APP_PATH="build/export/UsageBar.app"
MAIN_BIN="$APP_PATH/Contents/MacOS/UsageBar"
CLI_BIN="$APP_PATH/Contents/MacOS/usagebar-cli"

lipo -archs "$MAIN_BIN"
lipo -archs "$CLI_BIN"
```

Expected output for both binaries must contain:

- `arm64`
- `x86_64`

## 5. Package Unsigned ZIP and DMG

```bash
VERSION_TAG="v0.0.7"
APP_PATH="build/export/UsageBar.app"
ZIP_NAME="UsageBar-${VERSION_TAG}-unsigned.zip"
DMG_NAME="UsageBar-${VERSION_TAG}-unsigned.dmg"

mkdir -p ../dist/${VERSION_TAG}
ditto -c -k --keepParent "$APP_PATH" "../dist/${VERSION_TAG}/${ZIP_NAME}"

mkdir -p /tmp/usagebar-dmg-staging
rm -rf /tmp/usagebar-dmg-staging/*
cp -R "$APP_PATH" /tmp/usagebar-dmg-staging/
ln -s /Applications /tmp/usagebar-dmg-staging/Applications

hdiutil create -volname "UsageBar" \
  -srcfolder /tmp/usagebar-dmg-staging \
  -ov -format UDZO \
  "../dist/${VERSION_TAG}/${DMG_NAME}"
```

## 6. Generate SHA256

```bash
shasum -a 256 ../dist/${VERSION_TAG}/${ZIP_NAME}
shasum -a 256 ../dist/${VERSION_TAG}/${DMG_NAME}
```

## 7. Sign the Sparkle Update

UsageBar artifacts are not Apple-signed or notarized, but Sparkle update archives must still be signed with Sparkle's EdDSA key. Sparkle verifies this signature before installing an update.

```bash
SPARKLE_SIGN_UPDATE="/path/to/Sparkle/bin/sign_update"
ZIP_PATH="../dist/${VERSION_TAG}/${ZIP_NAME}"

printf '%s' "$SPARKLE_ED_PRIVATE_KEY" | "$SPARKLE_SIGN_UPDATE" --ed-key-file - "$ZIP_PATH"
```

Use the generated `sparkle:edSignature` and `length` values in the appcast enclosure.

## 8. Generate Sparkle Appcast

Generate release notes before generating the appcast. The release notes must be available in both forms:

- `release-notes.md` for the GitHub Release body
- `release-notes.html` for Sparkle

Use GitHub's generated release notes first. If GitHub does not produce concrete entries for the tag range, fall back to the commit summary from `PREVIOUS_TAG..HEAD`.

The generated `appcast.xml` must include:

- `sparkle:version`
- `sparkle:shortVersionString`
- `sparkle:minimumSystemVersion`
- `link` pointing to the GitHub Release page
- `sparkle:releaseNotesLink` pointing to `release-notes.html`
- `description` containing the HTML release notes
- an `enclosure` pointing to the ZIP archive
- `sparkle:edSignature`
- `length`

The automated `.github/workflows/manual-release.yml` workflow performs this step and uploads `appcast.xml` to the GitHub Release. The app reads it from:

```text
https://github.com/SHLE1/usage-bar/releases/latest/download/appcast.xml
```

## 9. Create Git Tag and Release

Every release must include release notes.

Release notes must also include:

- a note that the artifacts are **unsigned**
- the **`xattr` workaround** for Gatekeeper
- artifact names
- SHA256 values
- `appcast.xml`
- `release-notes.html`
- a note that Sparkle verifies updates with the appcast EdDSA signature

Example notice:

```md
## Notice
These artifacts are unsigned and not notarized, so macOS Gatekeeper may require manual override before opening.

After moving the app to Applications, run:

```bash
xattr -cr "/Applications/UsageBar.app"
```
```

Example release command:

```bash
git add .
git commit -m "chore: bump version to 0.0.7"
git tag v0.0.7
git push origin main --follow-tags

gh release create v0.0.7 \
  ../dist/v0.0.7/UsageBar-v0.0.7-unsigned.dmg \
  ../dist/v0.0.7/UsageBar-v0.0.7-unsigned.zip \
  ../dist/v0.0.7/appcast.xml \
  --title "UsageBar v0.0.7" \
  --notes-file /path/to/release-notes.md
```

## 10. Update Homebrew Tap

Every release must update `SHLE1/homebrew-tap`.

Update:

- `version`
- `sha256`
- `url`

Example cask target:

```ruby
cask "usage-bar" do
  version "0.0.7"
  sha256 "<DMG_SHA256>"

  url "https://github.com/SHLE1/usage-bar/releases/download/v#{version}/UsageBar-v#{version}-unsigned.dmg"
  name "UsageBar"
  desc "Menu bar app for AI provider usage monitoring"
  homepage "https://github.com/SHLE1/usage-bar"

  auto_updates true
  depends_on macos: ">= :ventura"

  app "UsageBar.app"
end
```

## GitHub Actions Workflows

Current workflows are aligned to the unsigned artifact process:

- `.github/workflows/build-release.yml`
  - Builds unsigned artifacts for validation on push / PR / manual run
  - Verifies universal binaries
  - Uploads unsigned ZIP and DMG artifacts

- `.github/workflows/manual-release.yml`
  - Calculates the next version from the latest tag
  - Updates version files
  - Builds unsigned artifacts
  - Verifies universal binaries
  - Signs the ZIP archive with Sparkle EdDSA
  - Generates release notes before the appcast, with a commit-summary fallback
  - Generates and uploads installable `appcast.xml` for Sparkle
  - Generates release notes including the `xattr` notice
  - Creates the GitHub Release
  - Updates `SHLE1/homebrew-tap`

## Troubleshooting

### Gatekeeper blocks the app

Run:

```bash
xattr -cr "/Applications/UsageBar.app"
```

### App cannot check for updates

Check that the latest GitHub Release contains `appcast.xml`:

```bash
gh release view --json assets --jq '.assets[].name'
```

If Check for Updates reports that an update is improperly signed, confirm the latest `appcast.xml` includes a ZIP enclosure with `sparkle:edSignature` and `length`, and confirm the signing key matches `SUPublicEDKey`.

### Workflow fails because tap update cannot run

Ensure `HOMEBREW_TAP_GITHUB_TOKEN` is configured and has push access to:

- `SHLE1/homebrew-tap`

### Universal binary verification fails

Check:

```bash
lipo -archs "build/export/UsageBar.app/Contents/MacOS/UsageBar"
lipo -archs "build/export/UsageBar.app/Contents/MacOS/usagebar-cli"
```
