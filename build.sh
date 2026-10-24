#!/bin/zsh
# Builds "MD Widgets.app" (Apple Silicon) next to this script.
#   VERSION=1.2 ./build.sh       version shown in Finder (default: 1.0)
#   SIGN_IDENTITY="Developer ID Application" ./build.sh
#                                sign for distribution instead of ad-hoc
set -euo pipefail
cd "$(dirname "$0")"

VERSION=${VERSION:-1.0}
BUILD=$(git rev-list --count HEAD 2>/dev/null || echo 1)
TRIPLE=arm64-apple-macosx14.0

swift build -c release --build-system native --triple $TRIPLE  # default backend fails on Command Line Tools
BIN="$(swift build -c release --build-system native --triple $TRIPLE --show-bin-path)/MDWidgets"
"$BIN" --selftest

APP="MD Widgets.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/"
cp Resources/AppIcon.icns "$APP/Contents/Resources/"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>MD Widgets</string>
    <key>CFBundleIdentifier</key><string>local.mdwidgets</string>
    <key>CFBundleExecutable</key><string>MDWidgets</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>$BUILD</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
</dict>
</plist>
PLIST

if [[ -n "${SIGN_IDENTITY:-}" ]]; then
    codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$APP"
else
    codesign --force --sign - "$APP"
fi
echo "Built $PWD/$APP ($VERSION, build $BUILD)"
