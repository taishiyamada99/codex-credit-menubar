#!/usr/bin/env bash
set -euo pipefail

APP_NAME="CodexCreditMenuBar"
BUNDLE_NAME="${APP_NAME}.app"
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="${ROOT_DIR}/.build/arm64-apple-macosx/release"
OUTPUT_DIR="${ROOT_DIR}/output"
APP_DIR="${OUTPUT_DIR}/${BUNDLE_NAME}"
EXECUTABLE_PATH="${BUILD_DIR}/${APP_NAME}"

mkdir -p "${OUTPUT_DIR}"

swift build -c release

if [[ ! -x "${EXECUTABLE_PATH}" ]]; then
  echo "error: executable not found: ${EXECUTABLE_PATH}" >&2
  exit 1
fi

rm -rf "${APP_DIR}"
mkdir -p "${APP_DIR}/Contents/MacOS"
mkdir -p "${APP_DIR}/Contents/Resources"

cp "${EXECUTABLE_PATH}" "${APP_DIR}/Contents/MacOS/${APP_NAME}"
chmod +x "${APP_DIR}/Contents/MacOS/${APP_NAME}"

cat > "${APP_DIR}/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleExecutable</key>
  <string>${APP_NAME}</string>
  <key>CFBundleIdentifier</key>
  <string>dev.codex.${APP_NAME}</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>${APP_NAME}</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>0.1.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSMinimumSystemVersion</key>
  <string>14.0</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
</dict>
</plist>
PLIST

echo "Created: ${APP_DIR}"
