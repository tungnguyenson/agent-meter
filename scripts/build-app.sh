#!/bin/bash
set -euo pipefail

# AgentMeter App Builder
# Usage: ./scripts/build-app.sh [version]

VERSION="${1:-1.0.0}"
APP_NAME="AgentMeter"
ZIP_NAME="${APP_NAME}-${VERSION}.zip"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="${PROJECT_DIR}/build"
APP_DIR="${BUILD_DIR}/Build/Products/Release"
APP_PATH="${APP_DIR}/${APP_NAME}.app"

echo "==> Building ${APP_NAME} v${VERSION}..."

xcodebuild -scheme "$APP_NAME" \
  -configuration Release \
  -derivedDataPath "$BUILD_DIR" \
  clean build \
  -quiet

if [ ! -d "$APP_PATH" ]; then
  echo "ERROR: Build failed - ${APP_PATH} not found"
  exit 1
fi

echo "==> Build successful"
echo "==> App directory: ${APP_DIR}"

# Remove old zip if it exists
# rm -f "${PROJECT_DIR}/${ZIP_NAME}"

# echo "==> Creating ZIP..."

# cd "${BUILD_DIR}/Build/Products/Release"
# ditto -c -k --keepParent "${APP_NAME}.app" "${PROJECT_DIR}/${ZIP_NAME}"

# echo ""
# echo "==> Done: ${ZIP_NAME} ($(du -h "${PROJECT_DIR}/${ZIP_NAME}" | cut -f1))"
