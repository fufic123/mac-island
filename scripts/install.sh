#!/usr/bin/env bash
# Installs the latest Mac Island release into /Applications and opens it.
#   curl -fsSL https://raw.githubusercontent.com/fufic123/mac-island/main/scripts/install.sh | bash
# Downloading with curl skips the Gatekeeper quarantine a browser download gets, so the
# unnotarized app opens normally. On first launch it offers to connect to Claude Code.
set -euo pipefail

REPO="fufic123/mac-island"
URL="https://github.com/$REPO/releases/latest/download/MacIsland.zip"
# /Applications, where the DMG puts it too; ~/Applications if that isn't writable.
DEST="/Applications"
[ -w "$DEST" ] || DEST="$HOME/Applications"

[ "$(uname -s)" = "Darwin" ] || { echo "Mac Island runs on macOS only." >&2; exit 1; }

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
echo "Downloading Mac Island…"
curl -fL --progress-bar "$URL" -o "$tmp/MacIsland.zip"
ditto -x -k "$tmp/MacIsland.zip" "$tmp"

pkill -x MacIsland 2>/dev/null || true
# An older install put it in ~/Applications; keep a single copy.
[ "$DEST" = "/Applications" ] && rm -rf "$HOME/Applications/MacIsland.app"
mkdir -p "$DEST"
rm -rf "$DEST/MacIsland.app"
ditto "$tmp/MacIsland.app" "$DEST/MacIsland.app"
xattr -dr com.apple.quarantine "$DEST/MacIsland.app" 2>/dev/null || true

open "$DEST/MacIsland.app"
echo "Installed to $DEST/MacIsland.app. Hover the notch to open the island."
