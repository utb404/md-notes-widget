#!/bin/zsh
# Builds "MD Widgets.app" next to this script.
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release --build-system native  # default backend fails on Command Line Tools
.build/release/MDWidgets --selftest

APP="MD Widgets.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp .build/release/MDWidgets "$APP/Contents/MacOS/"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>MD Widgets</string>
    <key>CFBundleIdentifier</key><string>local.mdwidgets</string>
    <key>CFBundleExecutable</key><string>MDWidgets</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
</dict>
</plist>
PLIST
codesign --force --sign - "$APP"
echo "Built $PWD/$APP"
