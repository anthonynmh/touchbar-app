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

if pgrep -x TouchbarPet >/dev/null 2>&1; then
    echo "==> stopping running instance..."
    pkill -x TouchbarPet 2>/dev/null || true
    sleep 1
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
