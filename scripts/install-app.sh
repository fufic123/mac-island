#!/usr/bin/env bash
# Builds Mac Island, installs it to ~/Applications and starts it at login via a LaunchAgent.
# launchd also restarts it if it crashes. Re-run after changes to update and restart it.
# --uninstall stops it and removes the app and the LaunchAgent.
set -euo pipefail

cd "$(dirname "$0")/.."
LABEL=com.fufic123.macisland
APP="$HOME/Applications/MacIsland.app"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
DOMAIN="gui/$(id -u)"

launchctl bootout "$DOMAIN/$LABEL" 2>/dev/null || true
pkill -x MacIsland 2>/dev/null || true

if [ "${1:-}" = "--uninstall" ]; then
  rm -f "$PLIST"
  rm -rf "$APP"
  echo "Removed Mac Island from login and ~/Applications."
  exit 0
fi

./scripts/bundle.sh
mkdir -p "$HOME/Applications" "$(dirname "$PLIST")"
rm -rf "$APP"
# Outside ~/Documents, so launchd can start it at login without a TCC block.
ditto build/MacIsland.app "$APP"

cat > "$PLIST" <<PL
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key><string>$LABEL</string>
    <key>ProgramArguments</key>
    <array><string>$APP/Contents/MacOS/MacIsland</string></array>
    <key>RunAtLoad</key><true/>
    <!-- Restart after a crash, not after a normal quit. -->
    <key>KeepAlive</key><dict><key>SuccessfulExit</key><false/></dict>
    <key>LimitLoadToSessionType</key><string>Aqua</string>
    <key>ProcessType</key><string>Interactive</string>
</dict>
</plist>
PL

launchctl bootstrap "$DOMAIN" "$PLIST"
echo "Installed $APP; it starts at login and is running now."
