#!/usr/bin/env bash
set -euo pipefail

root_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
release_dir="${RELEASE_DIR:-$root_dir/build/release}"
configuration="${CONFIGURATION:-Release}"
sign_identity="${SIGN_IDENTITY:-}"
notary_profile="${NOTARY_PROFILE:-}"
bundle_id="${BUNDLE_ID:-bar.pasteur.Pasteur}"
version="${VERSION:-}"
if [[ -z "$version" ]]; then
  version=$(git describe --tags --abbrev=0 2>/dev/null || true)
fi
if [[ -z "$version" ]]; then
  version="0.1.0"
fi

mkdir -p "$release_dir"

log() {
  echo "[release] $1"
}

log "Building web assets"
"$root_dir/scripts/build-web.sh"

log "Building macOS app (configuration=$configuration)"
if [[ -f "$root_dir/macos/Pasteur.xcodeproj/project.pbxproj" ]]; then
  xcodebuild \
    -project "$root_dir/macos/Pasteur.xcodeproj" \
    -scheme Pasteur \
    -configuration "$configuration" \
    -destination "platform=macOS" \
    CONFIGURATION_BUILD_DIR="$release_dir" \
    build
else
  xcodebuild \
    -scheme Pasteur \
    -configuration "$configuration" \
    -destination "platform=macOS" \
    CONFIGURATION_BUILD_DIR="$release_dir" \
    build
fi

app_path="$release_dir/Pasteur.app"
exec_path="$release_dir/Pasteur"
zip_path=""

if [[ ! -d "$app_path" ]]; then
  if [[ -f "$exec_path" ]]; then
    log "App bundle not found; creating $app_path"
    contents="$app_path/Contents"
    macos_bin="$contents/MacOS"
    resources="$contents/Resources"
    rm -rf "$app_path"
    mkdir -p "$macos_bin" "$resources"
    cp "$exec_path" "$macos_bin/Pasteur"

    resource_bundle="$release_dir/Pasteur_Pasteur.bundle/Contents/Resources"
    if [[ -d "$resource_bundle" ]]; then
      rsync -a "$resource_bundle/" "$resources/"
    elif [[ -d "$root_dir/macos/Pasteur/Resources" ]]; then
      rsync -a "$root_dir/macos/Pasteur/Resources/" "$resources/"
    fi

    cat > "$contents/Info.plist" <<EOF
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
  <string>$version</string>
  <key>CFBundleVersion</key>
  <string>$version</string>
  <key>NSHighResolutionCapable</key>
  <true/>
</dict>
</plist>
EOF
  else
    log "No build output found in $release_dir"
    exit 1
  fi
fi

log "Using app bundle at $app_path"
if [[ -n "$sign_identity" ]]; then
  log "Codesigning app"
  codesign --deep --force --options runtime --sign "$sign_identity" "$app_path"
fi

zip_path="$release_dir/Pasteur.app.zip"
log "Creating archive $zip_path"
ditto -c -k --sequesterRsrc --keepParent "$app_path" "$zip_path"

if [[ -n "$notary_profile" ]]; then
  log "Submitting for notarization"
  xcrun notarytool submit "$zip_path" --keychain-profile "$notary_profile" --wait
  log "Stapling notarization ticket"
  xcrun stapler staple "$app_path"
fi

log "Release artifact ready: $zip_path"
