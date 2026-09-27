#!/usr/bin/env bash
# Builds a universal release and packages build/FaceMacOS.dmg for GitHub Releases.
# Keep the asset name "FaceMacOS.dmg": the website downloads .../releases/latest/download/FaceMacOS.dmg.
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
DMG="build/FaceMacOS.dmg"

# dmgbuild lays out the drag-to-Applications window (background, icon positions) without scripting Finder.
if [[ ! -x .venv/bin/dmgbuild ]]; then
  python3 -m venv .venv
  .venv/bin/pip install --quiet dmgbuild
fi
if [[ ! -f Resources/dmg-background.tiff ]]; then
  WORK="$(mktemp -d)"
  swift scripts/make_dmg_background.swift "$WORK/bg.png" 1
  swift scripts/make_dmg_background.swift "$WORK/bg@2x.png" 2
  tiffutil -cathidpicheck "$WORK/bg.png" "$WORK/bg@2x.png" -out Resources/dmg-background.tiff >/dev/null
  rm -rf "$WORK"
fi

# Package a clean copy (no extended attributes) so the signature verifies on users' Macs.
STAGING="$(mktemp -d)"
trap 'rm -rf "$STAGING"' EXIT
ditto --norsrc --noextattr --noacl build/FaceMacOS.app "$STAGING/FaceMacOS.app"
codesign --verify --strict --deep "$STAGING/FaceMacOS.app"

rm -f "$DMG"
.venv/bin/dmgbuild -s scripts/dmg_settings.py -D app="$STAGING/FaceMacOS.app" "FaceMacOS" "$DMG" >/dev/null

if [[ -n "${SIGN_IDENTITY:-}" ]]; then
  codesign --force --sign "$SIGN_IDENTITY" --timestamp "$DMG"
fi
if [[ -n "${NOTARY_PROFILE:-}" ]]; then
  xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$DMG"
fi

echo "Created $DMG ($(du -h "$DMG" | cut -f1)) for version $VERSION"
