#!/bin/bash

set -euo pipefail

APP_NAME="Drop-off.app"
EXECUTABLE_NAME="Drop-off"
LEGACY_APP_NAME="Dropoff.app"
BUNDLE_IDENTIFIER="com.vojtechbrandejs.dropoff"
REPOSITORY="vojtasbrandejs/Drop-off"
SOURCE_REF="${DROPOFF_SOURCE_REF:-v1.1.1}"
SOURCE_ARCHIVE_URL="${DROPOFF_SOURCE_ARCHIVE_URL:-https://github.com/$REPOSITORY/archive/refs/tags/$SOURCE_REF.tar.gz}"
INSTALL_DIR="${DROPOFF_INSTALL_DIR:-/Applications}"
LAUNCH_AFTER_INSTALL="${DROPOFF_LAUNCH_AFTER_INSTALL:-1}"
TESTING="${DROPOFF_INSTALLER_TESTING:-0}"
WORK_DIR="$(/usr/bin/mktemp -d -t drop-off-source-install)"
ARCHIVE="$WORK_DIR/source.tar.gz"
SOURCE_DIR="$WORK_DIR/source"
TARGET_APP="$INSTALL_DIR/$APP_NAME"
LEGACY_APP="$INSTALL_DIR/$LEGACY_APP_NAME"
BACKUP_APP="$WORK_DIR/previous-$APP_NAME"
BACKUP_LEGACY_APP="$WORK_DIR/previous-$LEGACY_APP_NAME"
PREVIOUS_APP_MOVED=0
LEGACY_APP_MOVED=0
INSTALL_STARTED=0
INSTALL_COMPLETE=0

cleanup() {
    if [[ "$INSTALL_COMPLETE" != "1" ]]; then
        if [[ "$INSTALL_STARTED" == "1" ]]; then
            /bin/rm -rf "$TARGET_APP"
        fi
        if [[ "$PREVIOUS_APP_MOVED" == "1" && -e "$BACKUP_APP" ]]; then
            /bin/mv "$BACKUP_APP" "$TARGET_APP" 2>/dev/null || true
        fi
        if [[ "$LEGACY_APP_MOVED" == "1" && -e "$BACKUP_LEGACY_APP" ]]; then
            /bin/mv "$BACKUP_LEGACY_APP" "$LEGACY_APP" 2>/dev/null || true
        fi
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
        fail "refusing a source URL that is not HTTPS"
    fi
}

bundle_identifier() {
    /usr/libexec/PlistBuddy \
        -c "Print :CFBundleIdentifier" \
        "$1/Contents/Info.plist" \
        2>/dev/null || true
}

stop_running_app() {
    local process_name="$1"

    /usr/bin/pkill -TERM -x "$process_name" 2>/dev/null || true
    for _ in {1..30}; do
        if ! /usr/bin/pgrep -x "$process_name" >/dev/null 2>&1; then
            return
        fi
        /bin/sleep 0.1
    done
    fail "$process_name is still running; quit it and run the command again"
}

[[ "$(/usr/bin/uname -s)" == "Darwin" ]] || fail "macOS is required"
MACOS_MAJOR="$(/usr/bin/sw_vers -productVersion | /usr/bin/cut -d. -f1)"
(( MACOS_MAJOR >= 13 )) || fail "macOS 13 Ventura or newer is required"

if ! /usr/bin/xcrun --find swift >/dev/null 2>&1; then
    if [[ "$TESTING" != "1" ]]; then
        /usr/bin/xcode-select --install 2>/dev/null || true
    fi
    fail "Apple Command Line Tools are required. Finish their free installation, then run this command again."
fi

echo "Downloading Drop-off source $SOURCE_REF from GitHub…"
download "$SOURCE_ARCHIVE_URL" "$ARCHIVE"

/bin/mkdir -p "$SOURCE_DIR"
/usr/bin/tar -xzf "$ARCHIVE" --strip-components 1 -C "$SOURCE_DIR"

for required_path in \
    Package.swift \
    Sources/DropOff \
    packaging/Info.plist \
    scripts/build-app.sh; do
    [[ -e "$SOURCE_DIR/$required_path" ]] \
        || fail "the source archive is missing $required_path"
done

echo "Building Drop-off locally on this Mac…"
(
    cd "$SOURCE_DIR"
    DROPOFF_STAGING_ROOT="$WORK_DIR/staging" \
        DROPOFF_PACKAGE_DISTRIBUTION=0 \
        ./scripts/build-app.sh
)

SOURCE_APP="$SOURCE_DIR/.build/$APP_NAME"
[[ -d "$SOURCE_APP" ]] || fail "the local build did not create $APP_NAME"
[[ -x "$SOURCE_APP/Contents/MacOS/$EXECUTABLE_NAME" ]] \
    || fail "the local build is missing its executable"
[[ "$(bundle_identifier "$SOURCE_APP")" == "$BUNDLE_IDENTIFIER" ]] \
    || fail "the local build has an unexpected bundle identifier"
/usr/bin/codesign --verify --deep --strict "$SOURCE_APP" \
    || fail "the local build has an invalid code signature"
/usr/bin/lipo "$SOURCE_APP/Contents/MacOS/$EXECUTABLE_NAME" \
    -verify_arch arm64 x86_64 \
    || fail "the local build is not Universal 2"

stop_running_app "$EXECUTABLE_NAME"
stop_running_app "Dropoff"

if [[ "$INSTALL_DIR" == "/Applications" && ! -w "$INSTALL_DIR" ]]; then
    INSTALL_DIR="$HOME/Applications"
    TARGET_APP="$INSTALL_DIR/$APP_NAME"
    LEGACY_APP="$INSTALL_DIR/$LEGACY_APP_NAME"
    echo "Using $INSTALL_DIR because /Applications is not writable."
fi

/bin/mkdir -p "$INSTALL_DIR" || fail "could not create $INSTALL_DIR"
[[ -w "$INSTALL_DIR" ]] || fail "cannot write to $INSTALL_DIR"

if [[ -e "$TARGET_APP" ]]; then
    [[ "$(bundle_identifier "$TARGET_APP")" == "$BUNDLE_IDENTIFIER" ]] \
        || fail "$TARGET_APP belongs to a different application"
    PREVIOUS_APP_MOVED=1
    if ! /bin/mv "$TARGET_APP" "$BACKUP_APP"; then
        PREVIOUS_APP_MOVED=0
        fail "could not replace the existing app"
    fi
fi

if [[ -e "$LEGACY_APP" ]]; then
    [[ "$(bundle_identifier "$LEGACY_APP")" == "$BUNDLE_IDENTIFIER" ]] \
        || fail "$LEGACY_APP belongs to a different application"
    LEGACY_APP_MOVED=1
    if ! /bin/mv "$LEGACY_APP" "$BACKUP_LEGACY_APP"; then
        LEGACY_APP_MOVED=0
        fail "could not remove the obsolete Dropoff.app installation"
    fi
fi

INSTALL_STARTED=1
if ! COPYFILE_DISABLE=1 /usr/bin/ditto "$SOURCE_APP" "$TARGET_APP"; then
    fail "installation failed"
fi

if ! /usr/bin/codesign --verify --deep --strict "$TARGET_APP"; then
    fail "the installed app failed verification"
fi
if /usr/bin/xattr -p com.apple.quarantine "$TARGET_APP" >/dev/null 2>&1; then
    fail "the locally built app unexpectedly has a quarantine attribute"
fi

INSTALL_COMPLETE=1
/bin/rm -rf "$BACKUP_APP" "$BACKUP_LEGACY_APP"

echo "Installed the locally built Drop-off app in $INSTALL_DIR"
if [[ "$LAUNCH_AFTER_INSTALL" == "1" ]]; then
    /usr/bin/open "$TARGET_APP"
    echo "Drop-off is running in the menu bar."
fi
