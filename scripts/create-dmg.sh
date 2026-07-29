#!/bin/bash
set -euo pipefail

# AgentMeter DMG Builder
# Usage: ./scripts/create-dmg.sh [version]

VERSION="${1:-1.0.0}"
APP_NAME="AgentMeter"
DMG_NAME="${APP_NAME}-${VERSION}.dmg"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="${PROJECT_DIR}/build"
APP_PATH="${BUILD_DIR}/Build/Products/Release/${APP_NAME}.app"

# SKIP_BUILD lets a caller (e.g. CI, after it has already built, signed and
# stapled the app) package the existing app instead of rebuilding over it.
if [ -n "${SKIP_BUILD:-}" ]; then
  echo "==> SKIP_BUILD set — packaging existing app at ${APP_PATH}"
else
  echo "==> Building ${APP_NAME} v${VERSION}..."
  # XCODEBUILD_EXTRA_FLAGS lets a caller inject extra settings (e.g. signing)
  # without changing local behavior; it defaults to empty.
  xcodebuild -scheme "$APP_NAME" \
    -configuration Release \
    -derivedDataPath "$BUILD_DIR" \
    clean build \
    -quiet \
    ${XCODEBUILD_EXTRA_FLAGS:-}
fi

if [ ! -d "$APP_PATH" ]; then
  echo "ERROR: ${APP_PATH} not found"
  exit 1
fi

echo "==> Build successful"

rm -f "${PROJECT_DIR}/${DMG_NAME}"

echo "==> Creating DMG..."

dmgbuild \
  -s "${SCRIPT_DIR}/dmg-settings.py" \
  -D APP_PATH="$APP_PATH" \
  "$APP_NAME" \
  "${PROJECT_DIR}/${DMG_NAME}"

echo ""
echo "==> Done: ${DMG_NAME} ($(du -h "${PROJECT_DIR}/${DMG_NAME}" | cut -f1))"
echo ""
echo "GitHub release:"
echo "  git tag v${VERSION} && git push origin v${VERSION}"
echo "  gh release create v${VERSION} ${DMG_NAME} --title \"${APP_NAME} v${VERSION}\" --generate-notes"
