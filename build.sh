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

ICON_SRC="$ROOT_DIR/Resources/AppIcon.png"
if [[ -f "$ICON_SRC" ]]; then
  echo "==> Generating AppIcon.icns ..."
  swift "$ROOT_DIR/tools/make_icns.swift" "$ICON_SRC" "$APP_DIR/Contents/Resources/AppIcon.icns"

  # Bundle the full-color icon so the in-app UI can display it.
  cp "$ICON_SRC" "$APP_DIR/Contents/Resources/AppIcon.png"
fi

# Bundle a monochrome template glyph for the menu-bar item (tinted by macOS).
GLYPH_SRC="$ROOT_DIR/Resources/MenuBarGlyph.png"
if [[ -f "$GLYPH_SRC" ]]; then
  sips -z 36 36 "$GLYPH_SRC" --out "$APP_DIR/Contents/Resources/MenuBarIcon.png" >/dev/null
fi

echo "==> Ad-hoc code signing (required for notifications)..."
# Local ad-hoc builds must NOT use sandbox entitlements — the unresolved
# $(AppIdentifierPrefix) in keychain-access-groups prevents launch (POSIX 163).
# release.sh / Xcode archive applies PRowl.entitlements with a real team ID.
codesign --force --deep --sign - "$APP_DIR"

echo ""
echo "Done. Built: $APP_DIR"
echo "Run with:  open \"$APP_DIR\""
