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

The release script builds web assets, builds the macOS app, and packages a zip. It can also codesign and notarize if configured.

```bash
./scripts/release.sh
```

Optional environment variables:

- `RELEASE_DIR` (default: `build/release`)
- `CONFIGURATION` (default: `Release`)
- `SIGN_IDENTITY` (Developer ID Application name)
- `NOTARY_PROFILE` (keychain profile name for `notarytool`)

Example with signing + notarization:

```bash
SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
NOTARY_PROFILE="pasteur-notary" \
./scripts/release.sh
```
