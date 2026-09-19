#!/usr/bin/env bash
# Package an already built app and generate a signed Sparkle feed. Does not publish.
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="${1:?Usage: prepare_update.sh /path/to/PanaLux.app /path/to/output}"
OUT="${2:?Provide an empty output directory}"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP/Contents/Info.plist")"
TOOLS="$DIR/.build/artifacts/sparkle/Sparkle/bin"
mkdir -p "$OUT"
ARCHIVE="$OUT/PanaLux-${VERSION}.zip"
if [[ -e "$ARCHIVE" || -e "$OUT/appcast.xml" ]]; then
  echo 'Refusing to replace an existing archive or feed; use a new output directory.' >&2
  exit 1
fi
codesign --verify --deep --strict "$APP"
PUBLIC_KEY="$("$TOOLS/generate_keys" --account panalux -p)"
BUNDLED_KEY="$(/usr/libexec/PlistBuddy -c 'Print SUPublicEDKey' "$APP/Contents/Info.plist")"
[[ "$PUBLIC_KEY" == "$BUNDLED_KEY" ]] || { echo 'Signing key does not match app public key.' >&2; exit 1; }
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ARCHIVE"
"$TOOLS/generate_appcast" --account panalux --maximum-deltas 0 \
  --download-url-prefix "https://github.com/AnotherMeatsack/panalux/releases/download/v${VERSION}/" "$OUT"
echo "Prepared signed update: $ARCHIVE"
echo "Publish the archive and appcast.xml together on the new GitHub release."
