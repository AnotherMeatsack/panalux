#!/usr/bin/env bash
# Builds PanaLux.app (universal, ad-hoc signed) in the project root.
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

echo "==> Building ${APP_NAME} ${VERSION} (release)"
swift build -c release "${ARCH_FLAGS[@]}"
BIN_DIR="$(swift build -c release "${ARCH_FLAGS[@]}" --show-bin-path)"

APP_BUNDLE="${APP_NAME}.app"
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
    <key>NSHighResolutionCapable</key><true/>
    <key>NSSupportsAutomaticGraphicsSwitching</key><true/>
    <key>NSHumanReadableCopyright</key><string>Free and open source (MIT). Not affiliated with Blackmagic Design, Adobe, or Apple.</string>
    <key>NSAppleEventsUsageDescription</key><string>PanaLux asks Lightroom Classic and Photoshop to open, align, and save layered photos when you press Grab Still.</string>
</dict>
</plist>
PLIST

# Set PANALUX_SIGN_IDENTITY to a "Developer ID Application: …" identity to produce a
# build that can be notarized. Without it the app is ad-hoc signed and users have to
# use Open Anyway on first launch.
SIGN_IDENTITY="${PANALUX_SIGN_IDENTITY:-}"
if [[ -n "$SIGN_IDENTITY" ]]; then
    echo "==> Signing with ${SIGN_IDENTITY}"
    # Sign inside out: nested code first, then the bundle.
    find "$APP_BUNDLE" -name "*.bundle" -type d -print0 | while IFS= read -r -d '' nested; do
        codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$nested"
    done
    codesign --force --options runtime --timestamp \
        --entitlements Packaging/PanaLux.entitlements \
        --sign "$SIGN_IDENTITY" "$APP_BUNDLE"
    codesign --verify --strict --verbose=2 "$APP_BUNDLE"
else
    echo "==> Ad-hoc signing (set PANALUX_SIGN_IDENTITY for a notarizable build)"
    codesign --force --deep --sign - "$APP_BUNDLE"
fi

if strings -a "${CONTENTS}/MacOS/${APP_NAME}" | grep -q "${HOME}"; then
    echo "!! Warning: the binary still contains your home folder path." >&2
fi

echo "Built ${DIR}/${APP_BUNDLE}"
