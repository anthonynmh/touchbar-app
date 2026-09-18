#!/bin/bash
# wrap-as-app.sh <executable-path> <bundle-id> <output-dir> [bundle-name]
#
# Wraps a swift-build command-line executable in a minimal .app bundle so it
# can be activated (Touch Bar / NSApp.activate need a real bundle to work
# reliably on macOS 26).
#
# Prints the path to the produced .app on stdout.

set -euo pipefail

if [ $# -lt 3 ] || [ $# -gt 4 ]; then
    echo "usage: $0 <executable-path> <bundle-id> <output-dir> [bundle-name]" >&2
    exit 2
fi

EXEC_PATH="$1"
BUNDLE_ID="$2"
OUT_DIR="$3"
BUNDLE_NAME="${4:-$(basename "$EXEC_PATH")}"

if [[ ! "$BUNDLE_NAME" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] ||
   [ "$BUNDLE_NAME" = "." ] || [ "$BUNDLE_NAME" = ".." ]; then
    echo "error: unsafe bundle name: $BUNDLE_NAME" >&2
    exit 2
fi

if [[ ! "$BUNDLE_ID" =~ ^[A-Za-z0-9][A-Za-z0-9.-]*$ ]] ||
   [[ "$BUNDLE_ID" == *..* ]]; then
    echo "error: unsafe bundle identifier: $BUNDLE_ID" >&2
    exit 2
fi

case "/$OUT_DIR/" in
    */../*|*/./*)
        echo "error: output directory may not contain path traversal components: $OUT_DIR" >&2
        exit 2
        ;;
esac

if [ ! -x "$EXEC_PATH" ]; then
    echo "error: not executable: $EXEC_PATH" >&2
    exit 1
fi

if [ ! -d "$OUT_DIR" ] || [ -L "$OUT_DIR" ]; then
    echo "error: output directory must be an existing non-symlink directory: $OUT_DIR" >&2
    exit 1
fi

case "$OUT_DIR" in
    /*) OUT_ABSOLUTE="$OUT_DIR" ;;
    *) OUT_ABSOLUTE="$PWD/$OUT_DIR" ;;
esac

reject_symlink_components() {
    local path="$1"
    local remainder="${path#/}" component current=""
    while [ -n "$remainder" ]; do
        component="${remainder%%/*}"
        if [ "$component" = "$remainder" ]; then
            remainder=""
        else
            remainder="${remainder#*/}"
        fi
        [ -n "$component" ] || continue
        current="$current/$component"
        if [ -L "$current" ]; then
            echo "error: refusing symlinked output path component: $current" >&2
            return 1
        fi
    done
}

reject_symlink_components "$OUT_ABSOLUTE"
OUT_DIR=$(cd "$OUT_DIR" && pwd -P)

if [ "$(stat -f '%u' "$OUT_DIR")" -ne "$(id -u)" ] ||
   [ "$(stat -f '%Lp' "$OUT_DIR")" != "700" ]; then
    echo "error: output directory must be owned by the current user with mode 0700: $OUT_DIR" >&2
    exit 1
fi

APP_PATH="$OUT_DIR/${BUNDLE_NAME}.app"
CONTENTS="$APP_PATH/Contents"
MACOS_DIR="$CONTENTS/MacOS"
RESOURCES_DIR="$CONTENTS/Resources"

if [ -e "$APP_PATH" ] || [ -L "$APP_PATH" ]; then
    echo "error: destination already exists: $APP_PATH" >&2
    exit 1
fi

cleanup_partial_bundle() {
    if [ -d "$APP_PATH" ] && [ ! -L "$APP_PATH" ]; then
        rm -rf -- "$APP_PATH"
    fi
}
interrupted() {
    trap - EXIT HUP INT TERM
    cleanup_partial_bundle
    exit 130
}
trap cleanup_partial_bundle EXIT
trap interrupted HUP INT TERM

umask 077
mkdir "$APP_PATH"
mkdir "$CONTENTS" "$MACOS_DIR" "$RESOURCES_DIR"
cp "$EXEC_PATH" "$MACOS_DIR/$BUNDLE_NAME"
chmod +x "$MACOS_DIR/$BUNDLE_NAME"

cat > "$CONTENTS/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>$BUNDLE_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID</string>
    <key>CFBundleName</key>
    <string>$BUNDLE_NAME</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>0.0.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHumanReadableCopyright</key>
    <string>MIT</string>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>NSSupportsAutomaticTermination</key>
    <false/>
    <key>NSAppleEventsUsageDescription</key>
    <string>Snappy Nest reads Spotify playback state to animate the pet in sync with your music.</string>
</dict>
</plist>
EOF

trap - EXIT HUP INT TERM
echo "$APP_PATH"
