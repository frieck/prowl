#!/usr/bin/env bash
#
# Builds PRowl and assembles a macOS .app bundle.
# Usage: ./build.sh [debug|release]   (default: release)
#
set -euo pipefail

CONFIG="${1:-release}"
APP_NAME="PRowl"
DISPLAY_APP="PRowl.app"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="$ROOT_DIR/.build/$CONFIG"
APP_DIR="$ROOT_DIR/$DISPLAY_APP"

echo "==> Building ($CONFIG)..."
swift build -c "$CONFIG"

echo "==> Assembling $DISPLAY_APP ..."
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

cp "$BUILD_DIR/$APP_NAME" "$APP_DIR/Contents/MacOS/$APP_NAME"
cp "$ROOT_DIR/Resources/Info.plist" "$APP_DIR/Contents/Info.plist"
printf 'APPL????' > "$APP_DIR/Contents/PkgInfo"

if [[ -n "${VERSION:-}" ]]; then
  echo "==> Setting bundle version to $VERSION ..."
  plutil -replace CFBundleShortVersionString -string "$VERSION" "$APP_DIR/Contents/Info.plist"
  plutil -replace CFBundleVersion -string "$VERSION" "$APP_DIR/Contents/Info.plist"
fi

ICON_SRC="$ROOT_DIR/Resources/AppIcon.png"
if [[ -f "$ICON_SRC" ]]; then
  "$ROOT_DIR/scripts/compile-app-icons.sh" "$ROOT_DIR" "$APP_DIR/Contents/Resources"
fi

# Bundle a monochrome template glyph for the menu-bar item (tinted by macOS).
GLYPH_SRC="$ROOT_DIR/Resources/MenuBarGlyph.png"
if [[ -f "$GLYPH_SRC" ]]; then
  sips -z 36 36 "$GLYPH_SRC" --out "$APP_DIR/Contents/Resources/MenuBarIcon.png" >/dev/null
fi

echo "==> Ad-hoc code signing (required for notifications)..."
# Local ad-hoc builds must NOT use sandbox entitlements — the unresolved
# $(AppIdentifierPrefix) in keychain-access-groups prevents launch (SIGKILL).
# release.sh / Xcode archive applies PRowl.entitlements with a real team ID.
codesign --force --deep --sign - "$APP_DIR"

ENTITLEMENTS_XML=$(codesign --display --entitlements :- "$APP_DIR" 2>/dev/null || true)
if [[ -n "$ENTITLEMENTS_XML" && "$ENTITLEMENTS_XML" != *"<?xml"* ]]; then
  : # no entitlements embedded
elif [[ -n "$ENTITLEMENTS_XML" ]]; then
  echo ""
  echo "ERROR: $DISPLAY_APP was signed with entitlements. Ad-hoc builds cannot launch with"
  echo "       sandbox/keychain entitlements (unresolved AppIdentifierPrefix)."
  echo "       Rebuild with ./build.sh only, or use Xcode Debug without entitlements."
  exit 1
fi

codesign --verify --deep --strict "$APP_DIR"

echo ""
echo "Done. Built: $APP_DIR"
echo "Run with:  open \"$APP_DIR\""
