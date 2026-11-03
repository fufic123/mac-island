#!/usr/bin/env bash
# Packs build/MacIsland.app into build/MacIsland.dmg: opening it shows the app, an arrow and
# Applications, so installing is a drag.
set -euo pipefail
cd "$(dirname "$0")/.."

APP=build/MacIsland.app
DMG=build/MacIsland.dmg
VOL="Mac Island"
[ -d "$APP" ] || { echo "Build the app first (scripts/bundle.sh)." >&2; exit 1; }

tmp=$(mktemp -d)
trap 'hdiutil detach "/Volumes/$VOL" -quiet 2>/dev/null || true; rm -rf "$tmp"' EXIT

stage="$tmp/stage"
mkdir -p "$stage/.background"
ditto "$APP" "$stage/MacIsland.app"
ln -s /Applications "$stage/Applications"
swift scripts/make-dmg-background.swift "$tmp/bg.png" 1
swift scripts/make-dmg-background.swift "$tmp/bg@2x.png" 2
tiffutil -cathidpicheck "$tmp/bg.png" "$tmp/bg@2x.png" -out "$stage/.background/background.tiff" 2>/dev/null

hdiutil detach "/Volumes/$VOL" -quiet 2>/dev/null || true
hdiutil create -quiet -volname "$VOL" -srcfolder "$stage" -fs HFS+ -format UDRW -ov "$tmp/rw.dmg"
hdiutil attach -quiet -readwrite -noverify -noautoopen "$tmp/rw.dmg"

# Window layout. Needs Finder automation; without it the image still works, just unstyled.
if ! osascript <<OSA
tell application "Finder"
  tell disk "$VOL"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set the bounds of container window to {200, 120, 760, 502}
    set opts to the icon view options of container window
    set arrangement of opts to not arranged
    set icon size of opts to 100
    set text size of opts to 13
    set background picture of opts to file ".background:background.tiff"
    set position of item "MacIsland.app" of container window to {150, 170}
    set position of item "Applications" of container window to {410, 170}
    update without registering applications
    delay 1
    close
  end tell
end tell
OSA
then
  echo "Couldn't style the DMG window (Finder automation not allowed); it still installs fine." >&2
fi

sync
hdiutil detach -quiet "/Volumes/$VOL"
rm -f "$DMG"
hdiutil convert -quiet "$tmp/rw.dmg" -format UDZO -imagekey zlib-level=9 -o "$DMG"

# Left unsigned on purpose: a DMG signed with a self-signed identity is assessed by Gatekeeper
# and refused before it even mounts, while an unsigned one opens and the app inside gets the
# usual one-time "Open Anyway".
echo "Built $DMG"
