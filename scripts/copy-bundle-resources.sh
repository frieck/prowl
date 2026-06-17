#!/usr/bin/env bash
# Copies runtime bundle resources that aren't handled by the asset catalog.
set -euo pipefail

ROOT="${SRCROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
APP="${BUILT_PRODUCTS_DIR}/${PRODUCT_NAME}.app"
RES="$APP/Contents/Resources"

mkdir -p "$RES"

# Menu-bar template glyph (36px). Do not copy Resources/AppIcon.png here —
# it conflicts with AppIcon.icns / the asset catalog and breaks small Finder icons.
GLYPH="$ROOT/Resources/MenuBarGlyph.png"
if [[ -f "$GLYPH" ]]; then
  sips -z 36 36 "$GLYPH" --out "$RES/MenuBarIcon.png" >/dev/null
fi
