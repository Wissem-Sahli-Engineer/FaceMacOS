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

# Sparkle (in-app updates). Its XPC services are only needed by sandboxed apps.
mkdir -p "$APP/Contents/Frameworks"
ditto "$(dirname "$BIN")/Sparkle.framework" "$APP/Contents/Frameworks/Sparkle.framework"
rm -rf "$APP/Contents/Frameworks/Sparkle.framework/Versions/B/XPCServices" \
  "$APP/Contents/Frameworks/Sparkle.framework/XPCServices"

shopt -s nullglob
for model in Models/*.mlmodel Models/*.mlpackage; do
  xcrun coremlcompiler compile "$model" "$APP/Contents/Resources" >/dev/null
  echo "Compiled $(basename "$model")"
done

xattr -cr "$APP"
LOCAL_IDENTITY="FaceMacOS Local Signing"
if [[ -n "${SIGN_IDENTITY:-}" ]]; then
  SIGN_ARGS=(--options runtime --timestamp --sign "$SIGN_IDENTITY")
elif security find-certificate -c "$LOCAL_IDENTITY" >/dev/null 2>&1; then
  SIGN_ARGS=(--sign "$LOCAL_IDENTITY")
else
  echo "warning: ad-hoc signing; permissions reset on every rebuild. Run scripts/setup_signing.sh once." >&2
  SIGN_ARGS=(--sign -)
fi
# Inside out: Sparkle's helpers, then the framework, then the app. Sparkle only installs an update signed
# with the same certificate, so releases must always use the same identity.
SPARKLE="$APP/Contents/Frameworks/Sparkle.framework"
codesign --force "${SIGN_ARGS[@]}" "$SPARKLE/Versions/B/Autoupdate"
codesign --force "${SIGN_ARGS[@]}" "$SPARKLE/Versions/B/Updater.app"
codesign --force "${SIGN_ARGS[@]}" "$SPARKLE"
codesign --force "${SIGN_ARGS[@]}" --entitlements Resources/FaceMacOS.entitlements "$APP"
codesign --verify --strict --deep "$APP"
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
