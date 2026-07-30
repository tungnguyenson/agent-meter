#!/bin/bash
set -euo pipefail

# Rebuild AgentMeter and relaunch it
# Usage: ./scripts/rebuild-and-launch.sh [version]

VERSION="${1:-1.0.0}"
APP_NAME="AgentMeter"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
APP_PATH="${PROJECT_DIR}/build/Build/Products/Release/${APP_NAME}.app"

"${SCRIPT_DIR}/build-app.sh" "$VERSION"

echo "==> Quitting running ${APP_NAME} (if any)..."
osascript -e "tell application \"${APP_NAME}\" to quit" >/dev/null 2>&1 || true
pkill -x "$APP_NAME" >/dev/null 2>&1 || true

# Wait for the process to actually exit before relaunching
for _ in $(seq 1 20); do
  pgrep -x "$APP_NAME" >/dev/null 2>&1 || break
  sleep 0.2
done

echo "==> Launching ${APP_NAME}..."
open "$APP_PATH"
