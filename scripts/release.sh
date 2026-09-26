#!/usr/bin/env bash
# Builds a universal release and packages build/FaceMacOS-<version>.dmg for GitHub Releases.
# Optional: SIGN_IDENTITY="Developer ID Application: ..." and NOTARY_PROFILE=<notarytool keychain profile>
# to sign + notarize so users can open it without Gatekeeper warnings.
set -euo pipefail
cd "$(dirname "$0")/.."

if ! ls Models/FaceEmbedding.mlpackage >/dev/null 2>&1; then
  echo "error: Models/FaceEmbedding.mlpackage missing. Run scripts/convert_facenet.py first." >&2
  exit 1
fi

scripts/build.sh release

VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Resources/Info.plist)"
DMG="build/FaceMacOS-$VERSION.dmg"
STAGING="$(mktemp -d)"
trap 'rm -rf "$STAGING"' EXIT

cp -R build/FaceMacOS.app "$STAGING/"
ln -s /Applications "$STAGING/Applications"
rm -f "$DMG"
hdiutil create -volname "FaceMacOS" -srcfolder "$STAGING" -ov -format UDZO "$DMG" >/dev/null

if [[ -n "${SIGN_IDENTITY:-}" ]]; then
  codesign --force --sign "$SIGN_IDENTITY" --timestamp "$DMG"
fi
if [[ -n "${NOTARY_PROFILE:-}" ]]; then
  xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$DMG"
fi

echo "Created $DMG ($(du -h "$DMG" | cut -f1))"
