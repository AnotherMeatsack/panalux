#!/usr/bin/env bash
# Builds PanaLux.app in this checkout. Uses Developer ID when available; PANALUX_ADHOC=1 opts out.
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$DIR"

APP_NAME="PanaLux"
BUNDLE_ID="com.panalux.app"
VERSION="$(cat VERSION 2>/dev/null || echo 1.0.0)"
BUILD_NUMBER="$(date +%Y%m%d%H%M)"
ARCH_FLAGS=(--arch arm64 --arch x86_64)
if [[ "${PANALUX_NATIVE_ONLY:-0}" == "1" ]]; then
    ARCH_FLAGS=()
fi

cp RELEASE_NOTES.md Sources/PanaLux/Resources/ReleaseNotes.md

echo "==> Building ${APP_NAME} ${VERSION} (release)"
swift build -c release ${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"}
BIN_DIR="$(swift build -c release ${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"} --show-bin-path)"

APP_BUNDLE="${PANALUX_APP_BUNDLE:-${APP_NAME}.app}"
CONTENTS="${APP_BUNDLE}/Contents"
rm -rf "$APP_BUNDLE"
mkdir -p "${CONTENTS}/MacOS" "${CONTENTS}/Resources"

cp "${BIN_DIR}/${APP_NAME}" "${CONTENTS}/MacOS/${APP_NAME}"
strip -x "${CONTENTS}/MacOS/${APP_NAME}" 2>/dev/null || true
# SwiftPM stamps the deployment target as the SDK version. Record the real SDK so macOS
# gives the window current system styling; the minimum stays at 14.0.
SDK_VERSION="$(xcrun --sdk macosx --show-sdk-version)"
vtool -set-build-version macos 14.0 "${SDK_VERSION}" -replace \
    -output "${CONTENTS}/MacOS/${APP_NAME}.tmp" "${CONTENTS}/MacOS/${APP_NAME}"
mv "${CONTENTS}/MacOS/${APP_NAME}.tmp" "${CONTENTS}/MacOS/${APP_NAME}"
chmod +x "${CONTENTS}/MacOS/${APP_NAME}"

# SwiftPM resource bundle, plus a flat copy so lookups never depend on bundle layout.
if [[ -d "${BIN_DIR}/${APP_NAME}_${APP_NAME}.bundle" ]]; then
    cp -R "${BIN_DIR}/${APP_NAME}_${APP_NAME}.bundle" "${CONTENTS}/Resources/"
fi
# SwiftPM links Sparkle; the standalone app must embed its signed framework and helpers.
SPARKLE_ROOT="${DIR}/.build/artifacts/sparkle/Sparkle"
mkdir -p "${CONTENTS}/Frameworks"
ditto "${SPARKLE_ROOT}/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework" "${CONTENTS}/Frameworks/Sparkle.framework"
cp "${SPARKLE_ROOT}/LICENSE" "${CONTENTS}/Resources/Sparkle-LICENSE.txt"
SPARKLE_PUBLIC_KEY="$(cat Packaging/SparklePublicKey.txt)"
cp Sources/PanaLux/Resources/* "${CONTENTS}/Resources/"
cp Packaging/AppIcon.icns "${CONTENTS}/Resources/AppIcon.icns"
# The Lightroom plugin PanaLux installs for the user (GPL-3.0, see its NOTICE.txt).
cp -R "Packaging/PanaLux Bridge.lrplugin" "${CONTENTS}/Resources/"

cat > "${CONTENTS}/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key><string>en</string>
    <key>CFBundleDisplayName</key><string>${APP_NAME}</string>
    <key>CFBundleExecutable</key><string>${APP_NAME}</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundleIdentifier</key><string>${BUNDLE_ID}</string>
    <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
    <key>CFBundleName</key><string>${APP_NAME}</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>${VERSION}</string>
    <key>CFBundleVersion</key><string>${BUILD_NUMBER}</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.photography</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
    <key>SUFeedURL</key><string>https://github.com/AnotherMeatsack/panalux/releases/latest/download/appcast.xml</string>
    <key>SUPublicEDKey</key><string>${SPARKLE_PUBLIC_KEY}</string>
    <key>SUEnableAutomaticChecks</key><true/>
    <key>SUAutomaticallyUpdate</key><false/>
    <key>SUSendProfileInfo</key><false/>
    <key>SUVerifyUpdateBeforeExtraction</key><true/>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSSupportsAutomaticGraphicsSwitching</key><true/>
    <key>NSHumanReadableCopyright</key><string>Free and open source (MIT). Not affiliated with Blackmagic Design, Adobe, or Apple.</string>
    <key>NSAppleEventsUsageDescription</key><string>PanaLux asks Lightroom Classic and Photoshop to open, align, and save layered photos when you press Grab Still.</string>
</dict>
</plist>
PLIST

# Set PANALUX_SIGN_IDENTITY to a "Developer ID Application: …" identity to produce a
# build that can be notarized. Otherwise an available Developer ID is selected.
# With no identity (or PANALUX_ADHOC=1), use ad-hoc signing.
# An ad-hoc signature is a hash of the binary, so every rebuild looks like a different
# app to macOS and the Accessibility grant silently stops applying — the checkbox stays
# on while AXIsProcessTrusted() returns false. Signing with any Apple-issued identity
# gives a stable one, so the permission survives rebuilds. Developer ID is preferred
# because it is also what notarization needs; an Apple Development cert is enough to
# keep permissions stable locally.
SIGN_IDENTITY="${PANALUX_SIGN_IDENTITY:-}"
if [[ "${PANALUX_ADHOC:-0}" == "1" ]]; then
    SIGN_IDENTITY=""
elif [[ -z "$SIGN_IDENTITY" ]]; then
    # Resolve to the certificate's SHA-1, not its name: two certificates can share a
    # name, and codesign refuses an ambiguous one. Skip revoked certificates.
    pick_identity() {
        security find-identity -v -p codesigning 2>/dev/null \
            | grep -v CSSMERR \
            | grep "$1" \
            | head -1 \
            | awk '{print $2}'
    }
    # Developer ID only. An Apple Development certificate also gives a stable
    # identity, but a binary signed with one will not launch without a matching
    # provisioning profile, so it is worse than ad-hoc here.
    SIGN_IDENTITY="$(pick_identity 'Developer ID Application:' || true)"
    if [[ -n "$SIGN_IDENTITY" ]]; then
        SIGN_NAME="$(security find-identity -v -p codesigning 2>/dev/null | grep "$SIGN_IDENTITY" | sed 's/.*"\(.*\)".*/\1/' || true)"
    fi
fi

if [[ -n "$SIGN_IDENTITY" ]]; then
    # Resolve explicit fingerprints too: deciding runtime options from the supplied
    # text alone silently omitted hardened runtime for a Developer ID SHA-1.
    SIGN_NAME="$(security find-identity -v -p codesigning 2>/dev/null | awk -v identity="$SIGN_IDENTITY" '
        index($0, identity) { n=$0; sub(/^[^\"]*\"/, "", n); sub(/\".*$/, "", n); print n; exit }
    ')"
    if [[ "$SIGN_NAME" != Developer\ ID\ Application:* ]]; then
        echo "!! Choose a valid Developer ID Application identity, or PANALUX_ADHOC=1." >&2
        exit 1
    fi
    echo "==> Signing with ${SIGN_NAME:-$SIGN_IDENTITY}"
    # Sign Sparkle from the inside out, preserving the upstream helper entitlements.
    SPARKLE_FRAMEWORK="${CONTENTS}/Frameworks/Sparkle.framework"
    for component in "${SPARKLE_FRAMEWORK}/Versions/B/XPCServices/Downloader.xpc" \
                     "${SPARKLE_FRAMEWORK}/Versions/B/XPCServices/Installer.xpc" \
                     "${SPARKLE_FRAMEWORK}/Versions/B/Autoupdate" \
                     "${SPARKLE_FRAMEWORK}/Versions/B/Updater.app" \
                     "${SPARKLE_FRAMEWORK}"; do
        codesign --force --options runtime --timestamp --preserve-metadata=entitlements --sign "$SIGN_IDENTITY" "$component"
    done
    # Sign inside out: nested code first, then the bundle.
    find "$APP_BUNDLE" -name "*.bundle" -type d -print0 | while IFS= read -r -d '' nested; do
        codesign --force --sign "$SIGN_IDENTITY" "$nested"
    done
    if [[ "${SIGN_NAME:-$SIGN_IDENTITY}" == Developer\ ID* ]]; then
        codesign --force --options runtime --timestamp \
            --entitlements Packaging/PanaLux.entitlements \
            --sign "$SIGN_IDENTITY" "$APP_BUNDLE"
    else
        # No entitlements on a development certificate: those need a provisioning
        # profile to go with them, and without one the app will not launch at all.
        # All this signature is for is a stable identity, so permissions survive.
        codesign --force --sign "$SIGN_IDENTITY" "$APP_BUNDLE"
    fi
    codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"
else
    echo "==> Ad-hoc signing (set PANALUX_SIGN_IDENTITY for a notarizable build)"
    codesign --force --deep --sign - "$APP_BUNDLE"
fi

if strings -a "${CONTENTS}/MacOS/${APP_NAME}" | grep -q "${HOME}"; then
    echo "!! Warning: the binary still contains your home folder path." >&2
fi

echo "Built ${APP_BUNDLE}"
