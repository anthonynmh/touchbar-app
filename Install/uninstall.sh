#!/bin/bash
# uninstall.sh — remove Snappy Nest from /Applications and clear its
# preferences plist. Never touches anything else.

set -euo pipefail

if [ "$(id -u)" = "0" ]; then
    echo "error: refuse to run as root." >&2
    exit 1
fi

DEST="/Applications/TouchbarPet.app"
PREFS="$HOME/Library/Preferences/com.local.snappy-nest.plist"

# Stop every running copy, not only /Applications: `make run` and probe
# stagings run the same executable from a temporary bundle, and older dev
# builds were staged as SnappyNestDev. Match on the bundle executable path so
# unrelated processes are never touched. The perl MediaRemote host exits by
# itself once its parent is gone.
INSTANCE_PATTERN='\.app/Contents/MacOS/(TouchbarPet|SnappyNestDev)( |$)'
if pgrep -f "$INSTANCE_PATTERN" >/dev/null 2>&1; then
    echo "==> stopping running instance(s)..."
    pkill -f "$INSTANCE_PATTERN" 2>/dev/null || true
    for _ in {1..30}; do
        pgrep -f "$INSTANCE_PATTERN" >/dev/null 2>&1 || break
        sleep 0.1
    done
    if pgrep -f "$INSTANCE_PATTERN" >/dev/null 2>&1; then
        echo "==> instance did not exit; forcing"
        pkill -KILL -f "$INSTANCE_PATTERN" 2>/dev/null || true
        sleep 0.5
    fi
    pkill -f 'snappy_mediaremote_host' 2>/dev/null || true
fi

if [ -e "$DEST" ]; then
    echo "==> removing $DEST"
    rm -rf "$DEST"
else
    echo "$DEST not found (nothing to remove)."
fi

if [ -e "$PREFS" ]; then
    echo "==> removing preferences at $PREFS"
    rm -f "$PREFS"
fi

cat <<EOF

✅ Uninstalled.

If you enabled Launch at Login, open System Settings → General → Login Items
and remove the entry manually — this uninstaller never touches system
settings without confirmation.
EOF
