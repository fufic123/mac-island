#!/usr/bin/env bash
# Regenerates Resources/AppIcon.icns from scripts/make-icon.swift.
set -euo pipefail
cd "$(dirname "$0")/.."
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
swift scripts/make-icon.swift "$tmp/icon.png"
set_dir="$tmp/AppIcon.iconset"
mkdir "$set_dir"
for px in 16 32 128 256 512; do
  sips -z $px $px "$tmp/icon.png" --out "$set_dir/icon_${px}x${px}.png" >/dev/null
  sips -z $((px * 2)) $((px * 2)) "$tmp/icon.png" --out "$set_dir/icon_${px}x${px}@2x.png" >/dev/null
done
iconutil -c icns "$set_dir" -o Resources/AppIcon.icns
cp "$tmp/icon.png" Resources/AppIcon.png
echo "Wrote Resources/AppIcon.icns"
