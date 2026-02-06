#!/usr/bin/env bash
set -euo pipefail

root_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
release_dir="${RELEASE_DIR:-$root_dir/build/release}"
configuration="${CONFIGURATION:-Release}"
sign_identity="${SIGN_IDENTITY:-}"
notary_profile="${NOTARY_PROFILE:-}"

# In CI we always want distributable artifacts.
require_signing="${REQUIRE_SIGNING:-}"
require_notarization="${REQUIRE_NOTARIZATION:-}"
if [[ -z "$require_signing" ]]; then
  require_signing=$([[ "${GITHUB_ACTIONS:-}" == "true" ]] && echo "1" || echo "0")
fi
if [[ -z "$require_notarization" ]]; then
  require_notarization=$([[ "${GITHUB_ACTIONS:-}" == "true" ]] && echo "1" || echo "0")
fi

log() {
  echo "[release] $1"
}

fail() {
  echo "[release] ERROR: $1" >&2
  exit 1
}

mkdir -p "$release_dir"

# Resolve version (used for Info.plist).
app_version="${APP_VERSION:-}"
if [[ -z "$app_version" ]]; then
  if [[ -n "${GITHUB_REF_NAME:-}" ]]; then
    app_version="${GITHUB_REF_NAME#v}"
  elif git -C "$root_dir" describe --tags --match "v*" --abbrev=0 >/dev/null 2>&1; then
    app_version="$(git -C "$root_dir" describe --tags --match "v*" --abbrev=0)"
    app_version="${app_version#v}"
  else
    app_version="0.0.0"
  fi
fi

bundle_id="${BUNDLE_ID:-bar.pasteur.Pasteur}"
icon_source_png="${ICON_PNG:-$root_dir/docs/icon.png}"

if [[ "$require_signing" == "1" ]]; then
  if [[ -z "$sign_identity" || "$sign_identity" == "-" ]]; then
    fail "SIGN_IDENTITY must be set to a Developer ID Application identity (ad-hoc '-' is not allowed in CI)"
  fi
fi

if [[ "$require_notarization" == "1" && -z "$notary_profile" ]]; then
  fail "NOTARY_PROFILE must be set (notarytool keychain profile name)"
fi

if [[ -n "$notary_profile" ]]; then
  if [[ -z "$sign_identity" ]]; then
    fail "NOTARY_PROFILE is set but SIGN_IDENTITY is empty. Notarization requires Developer ID signing."
  fi
  if [[ "$sign_identity" == "-" ]]; then
    fail "NOTARY_PROFILE is set but SIGN_IDENTITY is ad-hoc ('-'). Notarization requires a Developer ID Application identity."
  fi
fi

log "Building web assets"
"$root_dir/scripts/build-web.sh"

build_products_dir="$release_dir/build-products"
rm -rf "$build_products_dir"
mkdir -p "$build_products_dir"

xcode_destination="${XCODE_DESTINATION:-generic/platform=macOS}"

log "Building macOS product via xcodebuild (configuration=$configuration, destination=$xcode_destination)"
if [[ -f "$root_dir/macos/Pasteur.xcodeproj/project.pbxproj" ]]; then
  xcodebuild \
    -project "$root_dir/macos/Pasteur.xcodeproj" \
    -scheme Pasteur \
    -configuration "$configuration" \
    -destination "$xcode_destination" \
    CONFIGURATION_BUILD_DIR="$build_products_dir" \
    build
else
  xcodebuild \
    -scheme Pasteur \
    -configuration "$configuration" \
    -destination "$xcode_destination" \
    CONFIGURATION_BUILD_DIR="$build_products_dir" \
    build
fi

app_path="$release_dir/Pasteur.app"
zip_path="$release_dir/Pasteur.app.zip"

built_app_path="$build_products_dir/Pasteur.app"
if [[ -d "$built_app_path" ]]; then
  log "Using app bundle produced by xcodebuild"
  rm -rf "$app_path"
  ditto "$built_app_path" "$app_path"
else
  binary_path="$build_products_dir/Pasteur"
  resource_bundle_path="$build_products_dir/Pasteur_Pasteur.bundle"

  [[ -f "$binary_path" ]] || fail "Expected executable not found at $binary_path"
  [[ -d "$resource_bundle_path" ]] || fail "Expected resource bundle not found at $resource_bundle_path"

  log "Creating app bundle at $app_path"
  rm -rf "$app_path"
  mkdir -p "$app_path/Contents/MacOS" "$app_path/Contents/Resources"

  ditto "$binary_path" "$app_path/Contents/MacOS/Pasteur"
  ditto "$resource_bundle_path" "$app_path/Contents/Resources/Pasteur_Pasteur.bundle"

  cat >"$app_path/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleExecutable</key>
  <string>Pasteur</string>
  <key>CFBundleIdentifier</key>
  <string>$bundle_id</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>Pasteur</string>
  <key>CFBundleDisplayName</key>
  <string>Pasteur</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>$app_version</string>
  <key>CFBundleVersion</key>
  <string>$app_version</string>
  <key>CFBundleIconFile</key>
  <string>Pasteur</string>
  <key>NSHighResolutionCapable</key>
  <true/>
</dict>
</plist>
EOF

  # Generate app icon (.icns) from a 1024x1024 PNG.
  if [[ -f "$icon_source_png" ]]; then
    log "Generating app icon from $icon_source_png"
    iconset_dir="$release_dir/icon.iconset"
    rm -rf "$iconset_dir"
    mkdir -p "$iconset_dir"

    sips -z 16 16     "$icon_source_png" --out "$iconset_dir/icon_16x16.png" >/dev/null
    sips -z 32 32     "$icon_source_png" --out "$iconset_dir/icon_16x16@2x.png" >/dev/null
    sips -z 32 32     "$icon_source_png" --out "$iconset_dir/icon_32x32.png" >/dev/null
    sips -z 64 64     "$icon_source_png" --out "$iconset_dir/icon_32x32@2x.png" >/dev/null
    sips -z 128 128   "$icon_source_png" --out "$iconset_dir/icon_128x128.png" >/dev/null
    sips -z 256 256   "$icon_source_png" --out "$iconset_dir/icon_128x128@2x.png" >/dev/null
    sips -z 256 256   "$icon_source_png" --out "$iconset_dir/icon_256x256.png" >/dev/null
    sips -z 512 512   "$icon_source_png" --out "$iconset_dir/icon_256x256@2x.png" >/dev/null
    sips -z 512 512   "$icon_source_png" --out "$iconset_dir/icon_512x512.png" >/dev/null
    sips -z 1024 1024 "$icon_source_png" --out "$iconset_dir/icon_512x512@2x.png" >/dev/null

    iconutil -c icns "$iconset_dir" -o "$app_path/Contents/Resources/Pasteur.icns"
    rm -rf "$iconset_dir"
  else
    log "Icon PNG not found at $icon_source_png (skipping .icns generation)"
  fi
fi

plutil -lint "$app_path/Contents/Info.plist" >/dev/null

log "App version: $app_version"

effective_sign_identity="$sign_identity"
developer_id_signing=1

# If no identity is provided, we still ad-hoc sign the .app so it doesn't show up as
# "damaged" (invalid signature). This does NOT satisfy Gatekeeper for typical users.
if [[ -z "$effective_sign_identity" ]]; then
  effective_sign_identity="-"
  developer_id_signing=0
elif [[ "$effective_sign_identity" == "-" ]]; then
  developer_id_signing=0
fi

if [[ "$developer_id_signing" == "1" ]]; then
  log "Codesigning (Developer ID)"
  codesign_args=(--force --options runtime --timestamp --sign "$effective_sign_identity")
else
  log "Codesigning (ad-hoc). Users will need to bypass Gatekeeper (right-click Open or remove quarantine)."
  codesign_args=(--force --sign "$effective_sign_identity")
fi

log "Codesigning nested components"
# Sign embedded frameworks/plugins first, then the app. Avoid --deep.
while IFS= read -r -d '' item; do
  codesign "${codesign_args[@]}" "$item"
done < <(
  find "$app_path/Contents" \
    \( \
      -name "*.framework" -o \
      -name "*.dylib" -o \
      -name "*.xpc" -o \
      -name "*.appex" -o \
      -name "*.plugin" -o \
      -name "*.app" \
    \) \
    -print0
)

log "Codesigning app"
codesign "${codesign_args[@]}" "$app_path"

log "Verifying codesign"
codesign --verify --strict --deep --verbose=4 "$app_path"

log "Creating archive $zip_path"
rm -f "$zip_path"
ditto -c -k --sequesterRsrc --keepParent "$app_path" "$zip_path"

if [[ -n "$notary_profile" ]]; then
  log "Submitting for notarization (profile=$notary_profile)"
  xcrun notarytool submit "$zip_path" --keychain-profile "$notary_profile" --wait

  log "Stapling notarization ticket"
  xcrun stapler staple "$app_path"
  xcrun stapler validate "$app_path"

  log "Gatekeeper assessment"
  spctl --assess --type execute --verbose=4 "$app_path"

  log "Re-creating archive (includes stapled ticket)"
  rm -f "$zip_path"
  ditto -c -k --sequesterRsrc --keepParent "$app_path" "$zip_path"
fi

log "Release artifact ready: $zip_path"
