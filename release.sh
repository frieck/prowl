#!/usr/bin/env bash
#
# Archives PRowl for Mac App Store submission (requires full Xcode, not CLT).
# Usage:
#   DEVELOPMENT_TEAM=XXXXXXXXXX ./release.sh
#
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

if ! xcodebuild -version >/dev/null 2>&1; then
  echo "Full Xcode is required (xcode-select -s /Applications/Xcode.app/Contents/Developer)"
  exit 1
fi

if [[ -z "${DEVELOPMENT_TEAM:-}" ]]; then
  echo "Set your Apple Team ID: DEVELOPMENT_TEAM=XXXXXXXXXX ./release.sh"
  exit 1
fi

./scripts/generate-xcodeproj.sh

ARCHIVE="$ROOT/build/PRowl.xcarchive"
EXPORT="$ROOT/build/export"
mkdir -p build

echo "==> Archiving (Release)..."
xcodebuild \
  -project PRowl.xcodeproj \
  -scheme PRowl \
  -configuration Release \
  DEVELOPMENT_TEAM="$DEVELOPMENT_TEAM" \
  -archivePath "$ARCHIVE" \
  archive

echo "==> Exporting for App Store..."
rm -rf "$EXPORT"
xcodebuild \
  -exportArchive \
  -archivePath "$ARCHIVE" \
  -exportPath "$EXPORT" \
  -exportOptionsPlist ExportOptions.plist

echo ""
echo "Export ready: $EXPORT"
echo "Upload with Transporter or: xcrun altool --upload-app -f \"$EXPORT/PRowl.pkg\" -t macos"
