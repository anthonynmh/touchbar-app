#!/bin/bash
# wrap-as-app.sh <executable-path> <bundle-id> <output-dir> [bundle-name]
#
# Wraps a swift-build command-line executable in a minimal .app bundle so it
# can be activated (Touch Bar / NSApp.activate need a real bundle to work
# reliably on macOS 26).
#
# Prints the path to the produced .app on stdout.

set -euo pipefail

if [ $# -lt 3 ]; then
    echo "usage: $0 <executable-path> <bundle-id> <output-dir> [bundle-name]" >&2
    exit 2
fi

EXEC_PATH="$1"
BUNDLE_ID="$2"
OUT_DIR="$3"
BUNDLE_NAME="${4:-$(basename "$EXEC_PATH")}"

if [ ! -x "$EXEC_PATH" ]; then
    echo "error: not executable: $EXEC_PATH" >&2
    exit 1
fi

APP_PATH="$OUT_DIR/${BUNDLE_NAME}.app"
CONTENTS="$APP_PATH/Contents"
MACOS_DIR="$CONTENTS/MacOS"
RESOURCES_DIR="$CONTENTS/Resources"

mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"
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

echo "$APP_PATH"
