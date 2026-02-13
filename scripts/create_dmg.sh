#!/usr/bin/env bash
set -euo pipefail

APP_NAME="CenterWindow"
DIST_DIR="dist"
APP_DIR="${DIST_DIR}/${APP_NAME}.app"
DMG_PATH="${DIST_DIR}/${APP_NAME}.dmg"

if [[ ! -d "${APP_DIR}" ]]; then
  echo "未找到 ${APP_DIR}，请先运行 scripts/build_app.sh"
  exit 1
fi

rm -f "${DMG_PATH}"

hdiutil create \
  -volname "${APP_NAME}" \
  -srcfolder "${APP_DIR}" \
  -ov \
  -format UDZO \
  "${DMG_PATH}"

echo "已生成: ${DMG_PATH}"
