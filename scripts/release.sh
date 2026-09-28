#!/usr/bin/env bash
# Builds a universal release, packages build/FaceMacOS.dmg, copies it to website/downloads/ and writes
# website/appcast.xml, which installed copies check for updates (Sparkle).
# Usage: NOTES="What's new in this version" scripts/release.sh
# Bump CFBundleShortVersionString and CFBundleVersion in Resources/Info.plist first.
# Optional: SIGN_IDENTITY="Developer ID Application: ..." and NOTARY_PROFILE=<notarytool keychain profile>
# to sign + notarize so users can open it without Gatekeeper warnings.
set -euo pipefail
cd "$(dirname "$0")/.."

SITE="https://facemacos.onrender.com"
APPCAST="website/appcast.xml"

if ! ls Models/FaceEmbedding.mlpackage >/dev/null 2>&1; then
  echo "error: Models/FaceEmbedding.mlpackage missing. Run scripts/convert_facenet.py first." >&2
  exit 1
fi

VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Resources/Info.plist)"
BUILD="$(/usr/libexec/PlistBuddy -c 'Print CFBundleVersion' Resources/Info.plist)"
# Sparkle offers an update only when its build number is higher than the installed one.
if [[ -f "$APPCAST" ]]; then
  PUBLISHED="$(sed -n 's:.*<sparkle\:version>\(.*\)</sparkle\:version>.*:\1:p' "$APPCAST" | head -1)"
  if [[ -n "$PUBLISHED" && "$BUILD" -le "$PUBLISHED" ]]; then
    echo "error: CFBundleVersion $BUILD must be higher than the published build $PUBLISHED. Bump it in Resources/Info.plist." >&2
    exit 1
  fi
fi

scripts/build.sh release
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

# The website serves this copy directly (Download buttons link to downloads/FaceMacOS.dmg).
mkdir -p website/downloads
cp "$DMG" website/downloads/FaceMacOS.dmg

# Sign the DMG with the Sparkle key in the login Keychain (created once with generate_keys) and publish
# it in the appcast. The ?v= query keeps caches from serving an older DMG under a newer signature.
SIGNATURE="$(.build/artifacts/sparkle/Sparkle/bin/sign_update "$DMG")"
cat > "$APPCAST" <<EOF
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>FaceMacOS</title>
    <item>
      <title>Version $VERSION</title>
      <pubDate>$(LC_ALL=C date -u "+%a, %d %b %Y %H:%M:%S +0000")</pubDate>
      <sparkle:version>$BUILD</sparkle:version>
      <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>13.0</sparkle:minimumSystemVersion>
      <description><![CDATA[${NOTES:-Improvements and fixes.}]]></description>
      <enclosure url="$SITE/downloads/FaceMacOS.dmg?v=$BUILD" type="application/octet-stream" $SIGNATURE />
    </item>
  </channel>
</rss>
EOF
echo "Created $DMG ($(du -h "$DMG" | cut -f1)) for version $VERSION ($BUILD)."
echo "Updated website/downloads/FaceMacOS.dmg and $APPCAST. Commit and push both to publish the update."
