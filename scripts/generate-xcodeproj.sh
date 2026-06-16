#!/usr/bin/env bash
# Regenerates PRowl.xcodeproj from project.yml (XcodeGen).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "XcodeGen is required. Install with: brew install xcodegen"
  exit 1
fi

echo "==> Preparing asset catalog icons..."
chmod +x scripts/prepare-appiconset.sh scripts/copy-bundle-resources.sh
./scripts/prepare-appiconset.sh

echo "==> Generating PRowl.xcodeproj from project.yml..."
xcodegen generate

echo "Done. Open PRowl.xcodeproj only when archiving; keep editing in Cursor."
