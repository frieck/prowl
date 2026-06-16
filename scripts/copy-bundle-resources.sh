#!/usr/bin/env bash
# Copies runtime bundle resources that aren't handled by the asset catalog.
set -euo pipefail

ROOT="${SRCROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
APP="${BUILT_PRODUCTS_DIR}/${PRODUCT_NAME}.app"
RES="$APP/Contents/Resources"

mkdir -p "$RES"

# Full-color icon used inside the popover UI.
if [[ -f "$ROOT/Resources/AppIcon.png" ]]; then
  cp "$ROOT/Resources/AppIcon.png" "$RES/AppIcon.png"
fi

# Menu-bar template glyph (36px).
GLYPH="$ROOT/Resources/MenuBarGlyph.png"
if [[ -f "$GLYPH" ]]; then
  sips -z 36 36 "$GLYPH" --out "$RES/MenuBarIcon.png" >/dev/null
fi
