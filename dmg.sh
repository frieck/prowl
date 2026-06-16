#!/usr/bin/env bash
#
# Builds PRowl.app and packages it as a drag-to-Install disk image.
# Usage:
#   ./dmg.sh                    # ad-hoc signed .app → build/PRowl.dmg
#   SIGN_IDENTITY="Developer ID Application: …" ./dmg.sh   # for distribution
#
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

APP_NAME="PRowl.app"
STAGING="$ROOT/build/dmg-staging"
DMG_PATH="$ROOT/build/PRowl.dmg"
VOLUME_NAME="PRowl"

echo "==> Building app..."
./build.sh release

if [[ -n "${SIGN_IDENTITY:-}" ]]; then
  echo "==> Signing with: $SIGN_IDENTITY"
  codesign --force --deep --options runtime --sign "$SIGN_IDENTITY" "$ROOT/$APP_NAME"
  codesign --verify --deep --strict "$ROOT/$APP_NAME"
fi

echo "==> Staging DMG contents..."
rm -rf "$STAGING"
mkdir -p "$STAGING"
cp -R "$ROOT/$APP_NAME" "$STAGING/"
ln -sf /Applications "$STAGING/Applications"

echo "==> Creating disk image..."
mkdir -p build
rm -f "$DMG_PATH"
hdiutil create \
  -volname "$VOLUME_NAME" \
  -srcfolder "$STAGING" \
  -ov \
  -format UDZO \
  "$DMG_PATH" >/dev/null

rm -rf "$STAGING"

echo ""
echo "Done: $DMG_PATH"
echo ""
echo "Local testing: open \"$DMG_PATH\""
echo ""
if [[ -z "${SIGN_IDENTITY:-}" ]]; then
  echo "Note: this DMG contains an ad-hoc signed app (fine for yourself)."
  echo "To distribute to others, re-run with a Developer ID certificate:"
  echo "  SIGN_IDENTITY=\"Developer ID Application: Your Name (TEAMID)\" ./dmg.sh"
  echo "Then notarize: xcrun notarytool submit \"$DMG_PATH\" --keychain-profile AC_PROFILE --wait"
  echo "               xcrun stapler staple \"$DMG_PATH\""
fi
