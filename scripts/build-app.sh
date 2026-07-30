#!/bin/bash

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ARM64_TRIPLE="arm64-apple-macosx13.0"
X86_64_TRIPLE="x86_64-apple-macosx13.0"
ARM64_BUILD_PATH="$(cd "$ROOT" && swift build -c release --triple "$ARM64_TRIPLE" --product DropOff --show-bin-path)"
X86_64_BUILD_PATH="$(cd "$ROOT" && swift build -c release --triple "$X86_64_TRIPLE" --product DropOff --show-bin-path)"
STAGING_ROOT="${DROPOFF_STAGING_ROOT:-/tmp/drop-off-build-$UID}"
APP="$STAGING_ROOT/Drop-off.app"
LIGHT_ICON_SOURCE="$ROOT/packaging/AppIconLight.png"
DARK_ICON_SOURCE="$ROOT/packaging/AppIconDark.png"
ICON_COMPOSER_SOURCE="$ROOT/packaging/AppIcon.icon"
LOCAL_APP="$ROOT/.build/Drop-off.app"
ARCHIVE="$ROOT/dist/Drop-off.app.zip"
ARCHIVE_CHECKSUM="$ARCHIVE.sha256"
DMG="$ROOT/dist/Drop-off.dmg"
DMG_CHECKSUM="$DMG.sha256"
DMG_SOURCE="$STAGING_ROOT/dmg"
LEGACY_APP="$ROOT/dist/Drop-off.app"
SIGNING_IDENTITY="${DROPOFF_SIGNING_IDENTITY:-}"
PACKAGE_DISTRIBUTION="${DROPOFF_PACKAGE_DISTRIBUTION:-1}"

cd "$ROOT"
swift build -c release --triple "$ARM64_TRIPLE" --product DropOff
swift build -c release --triple "$X86_64_TRIPLE" --product DropOff

rm -rf \
    "$STAGING_ROOT" \
    "$LOCAL_APP" \
    "$ARCHIVE" \
    "$ARCHIVE_CHECKSUM" \
    "$DMG" \
    "$DMG_CHECKSUM" \
    "$LEGACY_APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$ROOT/dist"

build_icon() {
    local source="$1"
    local name="$2"
    local iconset="$STAGING_ROOT/$name.iconset"

    mkdir -p "$iconset"
    while read -r filename size; do
        /usr/bin/sips -z "$size" "$size" "$source" \
            --out "$iconset/$filename" >/dev/null
    done <<'EOF'
icon_16x16.png 16
icon_16x16@2x.png 32
icon_32x32.png 32
icon_32x32@2x.png 64
icon_128x128.png 128
icon_128x128@2x.png 256
icon_256x256.png 256
icon_256x256@2x.png 512
icon_512x512.png 512
icon_512x512@2x.png 1024
EOF

    /usr/bin/iconutil -c icns "$iconset" \
        -o "$APP/Contents/Resources/$name.icns"
}

build_icon "$LIGHT_ICON_SOURCE" "AppIcon"
build_icon "$DARK_ICON_SOURCE" "AppIconDark"
/usr/bin/lipo -create \
    "$ARM64_BUILD_PATH/DropOff" \
    "$X86_64_BUILD_PATH/DropOff" \
    -output "$APP/Contents/MacOS/Drop-off"
/usr/bin/lipo "$APP/Contents/MacOS/Drop-off" -verify_arch arm64 x86_64
cp "$ROOT/packaging/Info.plist" "$APP/Contents/Info.plist"
cp "$ROOT/LICENSE" "$APP/Contents/Resources/LICENSE.txt"

# Xcode 26 compiles the Icon Composer source into appearance-aware assets.
# Command Line Tools and older Xcode releases keep the .icns fallback above.
XCODE_MAJOR=0
if [[ "$(/usr/bin/xcode-select -p)" != */CommandLineTools ]] \
    && XCODE_VERSION_OUTPUT="$(/usr/bin/xcodebuild -version 2>/dev/null)"; then
    XCODE_MAJOR="$(printf '%s\n' "$XCODE_VERSION_OUTPUT" | /usr/bin/awk '/^Xcode / { split($2, version, "."); print version[1] }')"
fi
if (( XCODE_MAJOR >= 26 )) \
    && ACTOOL_PATH="$(/usr/bin/xcrun --find actool 2>/dev/null)"; then
    "$ACTOOL_PATH" \
        --compile "$APP/Contents/Resources" \
        --platform macosx \
        --minimum-deployment-target 13.0 \
        --target-device mac \
        --app-icon AppIcon \
        --output-partial-info-plist "$STAGING_ROOT/AppIconInfo.plist" \
        "$ICON_COMPOSER_SOURCE" \
        >/dev/null
    /usr/libexec/PlistBuddy \
        -c "Add :CFBundleIconName string AppIcon" \
        "$APP/Contents/Info.plist"
    # CFBundleIconName is authoritative for the adaptive Icon Composer asset.
    # Keeping CFBundleIconFile here lets Finder select the light legacy .icns
    # instead of the compiled dark appearance on macOS 26.
    /usr/libexec/PlistBuddy \
        -c "Delete :CFBundleIconFile" \
        "$APP/Contents/Info.plist"
fi

chmod 755 "$APP/Contents/MacOS/Drop-off"

# Sign outside the file-provider-backed Documents folder. Finder metadata can
# otherwise be reattached between xattr cleanup and codesign verification.
/usr/bin/xattr -cr "$APP"
if [[ -n "$SIGNING_IDENTITY" ]]; then
    /usr/bin/codesign \
        --force \
        --deep \
        --options runtime \
        --timestamp \
        --sign "$SIGNING_IDENTITY" \
        "$APP"
    SIGNING_DESCRIPTION="Developer ID ($SIGNING_IDENTITY), hardened runtime and secure timestamp"
else
    /usr/bin/codesign --force --deep --sign - "$APP"
    SIGNING_DESCRIPTION="ad-hoc local signature (not for public distribution)"
fi
/usr/bin/xattr -cr "$APP"
/usr/bin/codesign --verify --deep --strict "$APP"
ln -s "$APP" "$LOCAL_APP"

echo "Built and signed: $LOCAL_APP -> $APP"
echo "Signing mode: $SIGNING_DESCRIPTION"

if [[ "$PACKAGE_DISTRIBUTION" == "1" ]]; then
    COPYFILE_DISABLE=1 /usr/bin/ditto -c -k --norsrc --keepParent "$APP" "$ARCHIVE"

    mkdir -p "$DMG_SOURCE"
    COPYFILE_DISABLE=1 /usr/bin/ditto "$APP" "$DMG_SOURCE/Drop-off.app"
    cp "$ROOT/LICENSE" "$DMG_SOURCE/LICENSE.txt"
    ln -s /Applications "$DMG_SOURCE/Applications"
    /usr/bin/hdiutil create \
        -quiet \
        -ov \
        -format UDZO \
        -imagekey zlib-level=9 \
        -volname "Drop-off" \
        -srcfolder "$DMG_SOURCE" \
        "$DMG"

    (
        cd "$ROOT/dist"
        /usr/bin/shasum -a 256 "Drop-off.app.zip" > "Drop-off.app.zip.sha256"
        /usr/bin/shasum -a 256 "Drop-off.dmg" > "Drop-off.dmg.sha256"
    )
    echo "Packaged for distribution:"
    echo "  $DMG"
    echo "  $ARCHIVE"
fi
