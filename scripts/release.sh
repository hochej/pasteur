#!/usr/bin/env bash
set -euo pipefail

root_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
release_dir="${RELEASE_DIR:-$root_dir/build/release}"
configuration="${CONFIGURATION:-Release}"
sign_identity="${SIGN_IDENTITY:-}"
notary_profile="${NOTARY_PROFILE:-}"

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

if [[ -d "$app_path" ]]; then
  log "Found app bundle at $app_path"
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
elif [[ -f "$exec_path" ]]; then
  log "App bundle not found; packaging executable"
  package_dir="$release_dir/Pasteur-executable"
  rm -rf "$package_dir"
  mkdir -p "$package_dir"
  cp "$exec_path" "$package_dir/"

  bundle_path="$release_dir/Pasteur_Pasteur.bundle"
  if [[ -d "$bundle_path" ]]; then
    cp -R "$bundle_path" "$package_dir/"
  fi

  if [[ -n "$sign_identity" ]]; then
    log "Codesigning executable"
    codesign --force --options runtime --sign "$sign_identity" "$package_dir/Pasteur"
  fi

  zip_path="$release_dir/Pasteur-macos.zip"
  log "Creating archive $zip_path"
  ditto -c -k --sequesterRsrc --keepParent "$package_dir" "$zip_path"
else
  log "No build output found in $release_dir"
  exit 1
fi

log "Release artifact ready: $zip_path"
