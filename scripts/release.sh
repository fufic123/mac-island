#!/usr/bin/env bash
# Builds the app and publishes it as a GitHub release: ./scripts/release.sh v0.2.0
set -euo pipefail
cd "$(dirname "$0")/.."
TAG=${1:?usage: release.sh <tag>}

./scripts/bundle.sh
rm -f build/MacIsland.zip
ditto -c -k --keepParent build/MacIsland.app build/MacIsland.zip
gh release create "$TAG" build/MacIsland.zip --title "Mac Island $TAG" --generate-notes
