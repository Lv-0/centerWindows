#!/usr/bin/env bash
set -euo pipefail

APP_NAME="CenterWindow"
BUNDLE_ID="${BUNDLE_ID:-com.comet.centerwindow}"
VERSION="${VERSION:-1.0.0}"
BUILD_DIR=".build/release"
DIST_DIR="dist"
APP_DIR="${DIST_DIR}/${APP_NAME}.app"
BINARY_PATH="${BUILD_DIR}/CenterWindow"
ICON_BUILD_DIR=".build/icons"
APP_ICON="${ICON_BUILD_DIR}/AppIcon.icns"
STATUS_ICON="${ICON_BUILD_DIR}/StatusIconTemplate.png"

echo "[1/4] 生成应用图标与状态栏图标"
scripts/generate_icons.sh

echo "[2/4] 构建 Release 二进制"
swift build -c release

echo "[3/4] 组装 .app Bundle"
rm -rf "${APP_DIR}"
mkdir -p "${APP_DIR}/Contents/MacOS"
mkdir -p "${APP_DIR}/Contents/Resources"

if [[ ! -f "${BINARY_PATH}" ]]; then
  echo "未找到可执行文件 ${BINARY_PATH}"
  exit 1
fi

cp "${BINARY_PATH}" "${APP_DIR}/Contents/MacOS/${APP_NAME}"
chmod +x "${APP_DIR}/Contents/MacOS/${APP_NAME}"
cp "${APP_ICON}" "${APP_DIR}/Contents/Resources/AppIcon.icns"
cp "${STATUS_ICON}" "${APP_DIR}/Contents/Resources/StatusIconTemplate.png"

cat > "${APP_DIR}/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key>
  <string>${APP_NAME}</string>
  <key>CFBundleDisplayName</key>
  <string>${APP_NAME}</string>
  <key>CFBundleIdentifier</key>
  <string>${BUNDLE_ID}</string>
  <key>CFBundleVersion</key>
  <string>${VERSION}</string>
  <key>CFBundleShortVersionString</key>
  <string>${VERSION}</string>
  <key>CFBundleExecutable</key>
  <string>${APP_NAME}</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundleSupportedPlatforms</key>
  <array>
    <string>MacOSX</string>
  </array>
  <key>LSMinimumSystemVersion</key>
  <string>13.0</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSHumanReadableCopyright</key>
  <string>Copyright © $(date +%Y)</string>
</dict>
</plist>
EOF

echo "APPL????" > "${APP_DIR}/Contents/PkgInfo"
echo "[4/4] 完成: ${APP_DIR}"
