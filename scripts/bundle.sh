#!/usr/bin/env bash
# Builds a release binary and wraps it into build/MacIsland.app.
set -euo pipefail

cd "$(dirname "$0")/.."
swift build -c release

APP=build/MacIsland.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$(swift build -c release --show-bin-path)/MacIsland" "$APP/Contents/MacOS/MacIsland"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>MacIsland</string>
    <key>CFBundleIdentifier</key><string>com.fufic123.macisland</string>
    <key>CFBundleExecutable</key><string>MacIsland</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.1.0</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
    <key>NSAppleEventsUsageDescription</key><string>Mac Island switches to the terminal tab running the Claude session you click.</string>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP" >/dev/null
echo "Built $APP"
