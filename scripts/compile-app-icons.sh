#!/usr/bin/env bash
# Compiles PRowl/Assets.xcassets into AppIcon.icns + Assets.car for the .app bundle.
# Requires Xcode (actool). Falls back to tools/make_icns.swift when actool is missing.
set -euo pipefail

ROOT="${1:?root dir}"
DEST="${2:?destination Resources dir}"
MASTER="$ROOT/Resources/AppIcon.png"
ASSETS="$ROOT/PRowl/Assets.xcassets"

mkdir -p "$DEST"

if [[ ! -f "$MASTER" ]]; then
  echo "warning: $MASTER not found, skipping app icon"
  exit 0
fi

"$ROOT/scripts/prepare-appiconset.sh"

ACTOOL=""
if [[ -n "${DEVELOPER_DIR:-}" && -x "${DEVELOPER_DIR}/usr/bin/actool" ]]; then
  ACTOOL="${DEVELOPER_DIR}/usr/bin/actool"
elif [[ -x "/Applications/Xcode.app/Contents/Developer/usr/bin/actool" ]]; then
  export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
  ACTOOL="$DEVELOPER_DIR/usr/bin/actool"
elif command -v xcrun >/dev/null 2>&1 && xcrun --find actool >/dev/null 2>&1; then
  ACTOOL="$(xcrun --find actool)"
fi

if [[ -n "$ACTOOL" ]]; then
  echo "==> Compiling app icon asset catalog (actool) ..."
  PARTIAL="$(mktemp -t prowl-actool.XXXXXX.plist)"
  "$ACTOOL" "$ASSETS" \
    --compile "$DEST" \
    --platform macosx \
    --minimum-deployment-target 13.0 \
    --app-icon AppIcon \
    --output-partial-info-plist "$PARTIAL"
  rm -f "$PARTIAL"
  exit 0
fi

echo "==> actool not found — generating AppIcon.icns via sips/iconutil ..."
echo "    (Install Xcode for Assets.car; Finder icons may not appear on recent macOS.)"
swift "$ROOT/tools/make_icns.swift" "$MASTER" "$DEST/AppIcon.icns"
