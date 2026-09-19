#!/usr/bin/env bash
# Builds PanaLux.app, then a drag-to-Applications disk image for GitHub Releases.
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$DIR"

if [[ -n "${PANALUX_NOTARY_PROFILE:-}" ]]; then
    if [[ -z "${PANALUX_SIGN_IDENTITY:-}" || "${PANALUX_ADHOC:-0}" == "1" ]]; then
        echo "!! Notarization requires an explicit Developer ID and PANALUX_ADHOC unset." >&2
        exit 1
    fi
    # Verify the saved profile before doing an expensive build. No secrets are read here.
    xcrun notarytool history --keychain-profile "$PANALUX_NOTARY_PROFILE" >/dev/null
fi

bash Scripts/build_app.sh

APP_NAME="PanaLux"
VERSION="$(cat VERSION 2>/dev/null || echo 1.0.0)"
DMG="${APP_NAME}-${VERSION}.dmg"
STAGING="$(mktemp -d)"
trap 'rm -rf "$STAGING"' EXIT

if [[ -n "${PANALUX_SIGN_IDENTITY:-}" && -n "${PANALUX_NOTARY_PROFILE:-}" ]]; then
    FIRST_LAUNCH_NOTE=""
else
    FIRST_LAUNCH_NOTE=" macOS stops it the first time because this
   build is not notarized. Open System Settings > Privacy & Security,
   scroll down, and click \"Open Anyway\" next to PanaLux."
fi
cp -R "${APP_NAME}.app" "$STAGING/"
ln -s /Applications "$STAGING/Applications"
cat > "$STAGING/Read Me First.txt" <<TXT
PanaLux ${VERSION}

1. Drag PanaLux into Applications.
2. Open PanaLux.${FIRST_LAUNCH_NOTE}
3. PanaLux does the rest: it installs its Lightroom plugin, checks
   the panel, and plays a short intro and hands-on tour.

PanaLux is a free, unofficial, open-source macOS app. It is not
affiliated with, endorsed by, or related to Blackmagic Design, Adobe,
or Apple.
TXT

rm -f "$DMG"
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGING" -ov -format UDZO "$DMG" >/dev/null

# Notarize when a Developer ID identity and a stored notarytool profile are both set.
# One-time setup:
#   xcrun notarytool store-credentials PanaLux --apple-id <you> --team-id <TEAM> --password <app-specific-password>
# Then:
#   PANALUX_SIGN_IDENTITY="Developer ID Application: … (TEAMID)" PANALUX_NOTARY_PROFILE=PanaLux ./Scripts/create_dmg.sh
# A development certificate carries a personal name. It is fine for local builds,
# where it keeps macOS permissions stable across rebuilds, but it must never be what
# ships. Packaging refuses it unless a Developer ID was chosen deliberately.
DMG_AUTHORITY="$(codesign -dv --verbose=2 "${APP_NAME}.app" 2>&1 | grep '^Authority=' | head -1 || true)"
if [[ "$DMG_AUTHORITY" == *"Apple Development"* && -z "${PANALUX_SIGN_IDENTITY:-}" ]]; then
    echo "!! ${APP_NAME}.app is signed with a development certificate, which carries a personal name." >&2
    echo "   Re-run as: PANALUX_ADHOC=1 ./Scripts/create_dmg.sh" >&2
    echo "   or set PANALUX_SIGN_IDENTITY to a Developer ID certificate." >&2
    exit 1
fi

NOTARY_PROFILE="${PANALUX_NOTARY_PROFILE:-}"
if [[ -n "${PANALUX_SIGN_IDENTITY:-}" && -n "$NOTARY_PROFILE" ]]; then
    echo "==> Signing the disk image"
    codesign --force --timestamp --sign "$PANALUX_SIGN_IDENTITY" "$DMG"
    echo "==> Notarizing (this takes a few minutes)"
    xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait \
        --output-format json > "$STAGING/notary-result.json"
    NOTARY_STATUS="$(plutil -extract status raw -o - "$STAGING/notary-result.json")"
    if [[ "$NOTARY_STATUS" != "Accepted" ]]; then
        cat "$STAGING/notary-result.json" >&2
        echo "!! Notarization was not accepted; do not distribute this image." >&2
        exit 1
    fi
    echo "==> Stapling"
    xcrun stapler staple "$DMG"
    xcrun stapler validate "$DMG"
    spctl --assess --type open --context context:primary-signature -vv "$DMG"
    echo "Notarized ${DIR}/${DMG}"
else
    echo "==> Not notarized. Set PANALUX_SIGN_IDENTITY and PANALUX_NOTARY_PROFILE to notarize."
fi
echo "Built ${DIR}/${DMG}"
