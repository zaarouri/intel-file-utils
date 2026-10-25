#!/bin/bash
set -e

echo "Building intel-file-utils for Intel Mac (x86_64)..."
swift build -c release

APP_NAME="Intel File Utils.app"
CONTENTS_DIR="${APP_NAME}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"

rm -rf "${APP_NAME}" "intel-file-utils.app" "floating-utils-intel-mac.app"
mkdir -p "${MACOS_DIR}" "${RESOURCES_DIR}"

cp .build/release/intel-file-utils "${MACOS_DIR}/intel-file-utils"
if [ -f "AppIcon.icns" ]; then
    cp AppIcon.icns "${RESOURCES_DIR}/AppIcon.icns"
fi
if [ -d "Resources" ]; then
    cp -R Resources/* "${RESOURCES_DIR}/"
fi

cat << 'PLIST' > "${CONTENTS_DIR}/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>
    <string>io.github.zaarouri.intel-file-utils</string>
    <key>CFBundleName</key>
    <string>Intel File Utils</string>
    <key>CFBundleDisplayName</key>
    <string>Intel File Utils</string>
    <key>CFBundleExecutable</key>
    <string>intel-file-utils</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSAppleEventsUsageDescription</key>
    <string>Intel File Utils observes global drag gestures to provide instant zero-click conversions in Finder.</string>
</dict>
</plist>
PLIST

# Create symlink for lowercase CLI convenience
ln -sfn "${APP_NAME}" "intel-file-utils.app"

echo "Codesigning app..."
codesign -s - --force --deep "${APP_NAME}"

echo "Intel File Utils.app packaged successfully!"
