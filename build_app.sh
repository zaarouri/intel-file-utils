#!/bin/bash
set -e

echo "Building floating-utils-intel-mac for Intel Mac (x86_64)..."
swift build -c release

APP_NAME="floating-utils-intel-mac.app"
CONTENTS_DIR="${APP_NAME}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"

rm -rf "${APP_NAME}"
mkdir -p "${MACOS_DIR}" "${RESOURCES_DIR}"

cp .build/release/floating-utils-intel-mac "${MACOS_DIR}/floating-utils-intel-mac"
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
    <string>com.local.floating-utils-intel-mac</string>
    <key>CFBundleName</key>
    <string>floating-utils-intel-mac</string>
    <key>CFBundleDisplayName</key>
    <string>floating-utils-intel-mac</string>
    <key>CFBundleExecutable</key>
    <string>floating-utils-intel-mac</string>
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
    <string>floating-utils-intel-mac detects selected files during drag gestures.</string>
</dict>
</plist>
PLIST

echo "Codesigning app..."
codesign -s - --force --deep "${APP_NAME}"

echo "floating-utils-intel-mac.app packaged successfully!"
