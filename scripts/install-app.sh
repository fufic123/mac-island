#!/usr/bin/env bash
# Builds Mac Island, installs it to /Applications and opens it. The app registers itself as a
# login item. Re-run after changes to update and restart it.
# --uninstall quits it and removes the app.
set -euo pipefail

cd "$(dirname "$0")/.."
LABEL=com.fufic123.macisland
APP=/Applications/MacIsland.app

# Clean up the older install style: a LaunchAgent plus a copy in ~/Applications.
launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
rm -f "$HOME/Library/LaunchAgents/$LABEL.plist"
rm -rf "$HOME/Applications/MacIsland.app"

pkill -x MacIsland 2>/dev/null || true

if [ "${1:-}" = "--uninstall" ]; then
  rm -rf "$APP"
  echo "Removed Mac Island."
  exit 0
fi

./scripts/bundle.sh
rm -rf "$APP"
ditto build/MacIsland.app "$APP"
open "$APP"
echo "Installed $APP and opened it; it starts at login."
