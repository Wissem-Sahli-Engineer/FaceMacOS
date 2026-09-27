#!/usr/bin/env bash
# Builds build/FaceMacOS.app. Usage: scripts/build.sh [debug|release] [--run]
# Set SIGN_IDENTITY (e.g. "Developer ID Application: Name (TEAMID)") to sign for distribution;
# otherwise the app is ad-hoc signed for local use.
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="release"
RUN=0
for arg in "$@"; do
  case "$arg" in
    debug|release) CONFIG="$arg" ;;
    --run) RUN=1 ;;
  esac
done

APP="build/FaceMacOS.app"
ARCH_FLAGS=()
if [[ "$CONFIG" == "release" ]]; then
  ARCH_FLAGS=(--arch arm64 --arch x86_64)
fi

swift build -c "$CONFIG" "${ARCH_FLAGS[@]}"
BIN="$(swift build -c "$CONFIG" "${ARCH_FLAGS[@]}" --show-bin-path)/FaceMacOS"

# Assemble and sign outside the project: iCloud-synced folders (Desktop/Documents) add Finder metadata
# that codesign rejects.
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
FINAL_APP="$APP"
APP="$WORK/FaceMacOS.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Library/LaunchAgents"
cp "$BIN" "$APP/Contents/MacOS/FaceMacOS"
cp Resources/LaunchAgents/*.plist "$APP/Contents/Library/LaunchAgents/"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

shopt -s nullglob
for model in Models/*.mlmodel Models/*.mlpackage; do
  xcrun coremlcompiler compile "$model" "$APP/Contents/Resources" >/dev/null
  echo "Compiled $(basename "$model")"
done

xattr -cr "$APP"
LOCAL_IDENTITY="FaceMacOS Local Signing"
if [[ -n "${SIGN_IDENTITY:-}" ]]; then
  codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" \
    --entitlements Resources/FaceMacOS.entitlements "$APP"
elif security find-certificate -c "$LOCAL_IDENTITY" >/dev/null 2>&1; then
  codesign --force --sign "$LOCAL_IDENTITY" --entitlements Resources/FaceMacOS.entitlements "$APP"
else
  echo "warning: ad-hoc signing; permissions reset on every rebuild. Run scripts/setup_signing.sh once." >&2
  codesign --force --sign - --entitlements Resources/FaceMacOS.entitlements "$APP"
fi
codesign --verify --strict "$APP"
rm -rf "$FINAL_APP"
mkdir -p "$(dirname "$FINAL_APP")"
ditto "$APP" "$FINAL_APP"
APP="$FINAL_APP"
echo "Built $APP"

if [[ "$RUN" == 1 ]]; then
  pkill -x FaceMacOS 2>/dev/null || true
  sleep 0.5
  open "$APP"
fi
