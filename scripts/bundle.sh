#!/usr/bin/env bash
# Builds a release binary and wraps it into build/MacIsland.app.
set -euo pipefail

cd "$(dirname "$0")/.."
swift build -c release

APP=build/MacIsland.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$(swift build -c release --show-bin-path)/MacIsland" "$APP/Contents/MacOS/MacIsland"
mkdir -p "$APP/Contents/Resources"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
# The app connects itself to Claude Code on first launch with these.
cp scripts/island-hook.sh scripts/install-hooks.sh "$APP/Contents/Resources/"
chmod +x "$APP/Contents/Resources/"*.sh

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>MacIsland</string>
    <key>CFBundleIdentifier</key><string>com.fufic123.macisland</string>
    <key>CFBundleExecutable</key><string>MacIsland</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.3.0</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundleDisplayName</key><string>Mac Island</string>
    <key>CFBundleVersion</key><string>3</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>LSApplicationCategoryType</key><string>public.app-category.developer-tools</string>
    <key>NSAppleEventsUsageDescription</key><string>Mac Island switches to the terminal tab running the Claude session you click.</string>
</dict>
</plist>
PLIST

# A stable identity (scripts/make-signing-identity.sh) keeps granted permissions across rebuilds;
# an ad-hoc signature changes with every build, so macOS treats each build as a new app.
IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null | awk -F'"' '/MacIsland Local Signing/ {print $2; exit}')
codesign --force --sign "${IDENTITY:--}" "$APP" >/dev/null
[ -n "$IDENTITY" ] || echo "Signed ad-hoc; run scripts/make-signing-identity.sh once so permissions survive rebuilds."
echo "Built $APP"
