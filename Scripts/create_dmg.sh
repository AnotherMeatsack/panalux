#!/usr/bin/env bash
# Builds PanaLux.app, then a drag-to-Applications disk image for GitHub Releases.
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$DIR"

bash Scripts/build_app.sh

APP_NAME="PanaLux"
VERSION="$(cat VERSION 2>/dev/null || echo 1.0.0)"
DMG="${APP_NAME}-${VERSION}.dmg"
STAGING="$(mktemp -d)"
trap 'rm -rf "$STAGING"' EXIT

cp -R "${APP_NAME}.app" "$STAGING/"
ln -s /Applications "$STAGING/Applications"
cat > "$STAGING/Read Me First.txt" <<TXT
PanaLux ${VERSION}

1. Drag PanaLux into Applications.
2. Open PanaLux. macOS stops it the first time because it is free
   and not notarized. Open System Settings > Privacy & Security,
   scroll down, and click "Open Anyway" next to PanaLux.
3. PanaLux does the rest: it installs its Lightroom plugin, checks
   the panel, and plays a short intro and hands-on tour.

PanaLux is a free, unofficial, open-source macOS app. It is not
affiliated with, endorsed by, or related to Blackmagic Design, Adobe,
or Apple.
TXT

rm -f "$DMG"
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGING" -ov -format UDZO "$DMG" >/dev/null
echo "Built ${DIR}/${DMG}"
