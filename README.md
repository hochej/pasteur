# Pasteur

<p align="center">
  <img src="docs/icon.png" alt="Pasteur logo" width="96" height="96" />
</p>

Pasteur is a macOS menu bar app for instant molecular structure visualization from clipboard content (PDB/mmCIF/XYZ/MOL/SDF/MOL2).

## Development

```bash
# Build web assets and copy into macOS bundle
./scripts/build-web.sh

# Build the app (SwiftPM)
swift build
```

## Release

The release script builds web assets, builds the SwiftPM executable, wraps it into a `Pasteur.app`, and packages `Pasteur.app.zip`.

```bash
./scripts/release.sh
```

Environment variables:

- `RELEASE_DIR` (default: `build/release`)
- `CONFIGURATION` (default: `Release`)
- `APP_VERSION` (default: derived from the current `v*` git tag, else `0.0.0`)
- `BUNDLE_ID` (default: `bar.pasteur.Pasteur`)
- `SIGN_IDENTITY` (Developer ID Application identity; required for distribution)
- `NOTARY_PROFILE` (keychain profile name for `notarytool`; required for Gatekeeper-friendly releases)

Create a notarytool profile (one-time on your machine):

```bash
xcrun notarytool store-credentials "pasteur-notary" \
  --apple-id "you@example.com" \
  --team-id "TEAMID" \
  --password "APP_SPECIFIC_PASSWORD"
```

Example build with signing + notarization:

```bash
SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
NOTARY_PROFILE="pasteur-notary" \
./scripts/release.sh
```

### GitHub Releases

The tag-based workflow (`.github/workflows/release.yml`) expects these repository secrets:

- `MACOS_CERTIFICATE_P12_BASE64`
- `MACOS_CERTIFICATE_PASSWORD`
- `MACOS_SIGN_IDENTITY`
- `APPLE_ID`
- `APPLE_TEAM_ID`
- `APPLE_APP_SPECIFIC_PASSWORD`
