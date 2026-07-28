#!/bin/bash

set -euo pipefail

APP_NAME="Drop-off.app"
EXECUTABLE_NAME="Drop-off"
REPOSITORY="vojtasbrandejs/Drop-off"
RELEASE_BASE_URL="${DROPOFF_RELEASE_BASE_URL:-https://github.com/$REPOSITORY/releases/latest/download}"
INSTALL_DIR="${DROPOFF_INSTALL_DIR:-/Applications}"
LAUNCH_AFTER_INSTALL="${DROPOFF_LAUNCH_AFTER_INSTALL:-1}"
TESTING="${DROPOFF_INSTALLER_TESTING:-0}"
WORK_DIR="$(/usr/bin/mktemp -d -t drop-off-install)"
ZIP_NAME="$APP_NAME.zip"
CHECKSUM_NAME="$ZIP_NAME.sha256"
EXTRACT_DIR="$WORK_DIR/extracted"
SOURCE_APP="$EXTRACT_DIR/$APP_NAME"
TARGET_APP="$INSTALL_DIR/$APP_NAME"
BACKUP_APP="$WORK_DIR/previous-$APP_NAME"
PREVIOUS_APP_MOVED=0

cleanup() {
    if [[ "$PREVIOUS_APP_MOVED" == "1" && -e "$BACKUP_APP" ]]; then
        /bin/rm -rf "$TARGET_APP"
        /bin/mv "$BACKUP_APP" "$TARGET_APP" 2>/dev/null || true
    fi
    /bin/rm -rf "$WORK_DIR"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

fail() {
    echo "Drop-off installer: $*" >&2
    exit 1
}

download() {
    local url="$1"
    local destination="$2"

    if [[ "$url" == https://* ]]; then
        /usr/bin/curl \
            --proto "=https" \
            --tlsv1.2 \
            --fail \
            --location \
            --silent \
            --show-error \
            --retry 3 \
            --output "$destination" \
            "$url"
    elif [[ "$TESTING" == "1" && "$url" == file://* ]]; then
        /usr/bin/curl \
            --fail \
            --location \
            --silent \
            --show-error \
            --output "$destination" \
            "$url"
    else
        fail "refusing a non-HTTPS release URL"
    fi
}

[[ "$(/usr/bin/uname -s)" == "Darwin" ]] || fail "macOS is required"
MACOS_MAJOR="$(/usr/bin/sw_vers -productVersion | /usr/bin/cut -d. -f1)"
(( MACOS_MAJOR >= 13 )) || fail "macOS 13 Ventura or newer is required"

echo "Downloading the latest Drop-off release…"
download "$RELEASE_BASE_URL/$ZIP_NAME" "$WORK_DIR/$ZIP_NAME"
download "$RELEASE_BASE_URL/$CHECKSUM_NAME" "$WORK_DIR/$CHECKSUM_NAME"

(
    cd "$WORK_DIR"
    /usr/bin/shasum -a 256 -c "$CHECKSUM_NAME"
) >/dev/null || fail "the downloaded app did not match its published checksum"

/bin/mkdir -p "$EXTRACT_DIR"
/usr/bin/ditto -x -k "$WORK_DIR/$ZIP_NAME" "$EXTRACT_DIR"

[[ -d "$SOURCE_APP" ]] || fail "the release archive does not contain $APP_NAME"
[[ -x "$SOURCE_APP/Contents/MacOS/$EXECUTABLE_NAME" ]] \
    || fail "the release archive is missing its executable"
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$SOURCE_APP/Contents/Info.plist")" \
    == "com.vojtechbrandejs.dropoff" ]] \
    || fail "the release archive has an unexpected bundle identifier"
/usr/bin/codesign --verify --deep --strict "$SOURCE_APP" \
    || fail "the downloaded app has an invalid code signature"
/usr/bin/lipo "$SOURCE_APP/Contents/MacOS/$EXECUTABLE_NAME" \
    -verify_arch arm64 x86_64 \
    || fail "the downloaded app is not a Universal 2 build"

if /usr/bin/pgrep -x "$EXECUTABLE_NAME" >/dev/null 2>&1; then
    fail "Drop-off is running. Quit it from the menu bar, then run this command again."
fi

/bin/mkdir -p "$INSTALL_DIR" \
    || fail "could not create $INSTALL_DIR"
[[ -w "$INSTALL_DIR" ]] \
    || fail "cannot write to $INSTALL_DIR. Install manually with the DMG instead."

if [[ -e "$TARGET_APP" ]]; then
    PREVIOUS_APP_MOVED=1
    if ! /bin/mv "$TARGET_APP" "$BACKUP_APP"; then
        PREVIOUS_APP_MOVED=0
        fail "could not replace the existing app"
    fi
fi

if ! COPYFILE_DISABLE=1 /usr/bin/ditto "$SOURCE_APP" "$TARGET_APP"; then
    /bin/rm -rf "$TARGET_APP"
    if [[ -e "$BACKUP_APP" ]]; then
        /bin/mv "$BACKUP_APP" "$TARGET_APP"
    fi
    fail "installation failed; the previous app was restored"
fi

if ! /usr/bin/codesign --verify --deep --strict "$TARGET_APP"; then
    /bin/rm -rf "$TARGET_APP"
    if [[ -e "$BACKUP_APP" ]]; then
        /bin/mv "$BACKUP_APP" "$TARGET_APP"
    fi
    fail "the installed app failed verification; the previous app was restored"
fi

PREVIOUS_APP_MOVED=0
/bin/rm -rf "$BACKUP_APP"

echo "Installed Drop-off in $INSTALL_DIR"
if [[ "$LAUNCH_AFTER_INSTALL" == "1" ]]; then
    /usr/bin/open "$TARGET_APP"
    echo "Drop-off is running in the menu bar."
fi
