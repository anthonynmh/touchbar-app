#!/bin/bash
# install.sh — build Snappy Nest and copy the .app into /Applications.
#
# What this does:
#   1. sanity-checks: not root, macOS ≥ 26, arm64, Xcode present
#   2. swift build -c release
#   3. wraps the TouchbarPet executable in a minimal .app bundle
#   4. asks before overwriting an existing /Applications/TouchbarPet.app
#   5. prints the escape-hatch shortcut and where to find README.md
#
# What this does NOT do:
#   - never runs as root
#   - never touches /System or /Library
#   - never installs privileged helpers
#   - never enables launch-at-login silently (Preferences opt-in)
#   - never makes a network request

set -euo pipefail

if [ "$(id -u)" = "0" ]; then
    echo "error: refuse to run as root. Run as your normal user." >&2
    exit 1
fi

REPO="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO"

# ---- 1. sanity checks ------------------------------------------------------

case "$(uname -s)" in
    Darwin) ;;
    *) echo "error: this app is macOS-only." >&2; exit 1 ;;
esac

case "$(uname -m)" in
    arm64) ;;
    *) echo "error: this app targets Apple Silicon (arm64)." >&2; exit 1 ;;
esac

MACOS_MAJOR=$(sw_vers -productVersion | cut -d. -f1)
if [ "$MACOS_MAJOR" -lt 26 ]; then
    echo "error: macOS 26 (Tahoe) or later required. Found $(sw_vers -productVersion)." >&2
    exit 1
fi

if ! xcode-select -p >/dev/null 2>&1; then
    echo "error: Xcode command-line tools not found. Install Xcode first." >&2
    exit 1
fi

# ---- 2. build --------------------------------------------------------------

echo "==> building TouchbarPet (release)..."
swift build -c release --product TouchbarPet

EXEC_PATH="$REPO/.build/release/TouchbarPet"
if [ ! -x "$EXEC_PATH" ]; then
    echo "error: build did not produce $EXEC_PATH" >&2
    exit 1
fi

# ---- 3. wrap as .app -------------------------------------------------------

STAGE_DIR="$REPO/build/stage"
mkdir -p "$STAGE_DIR"
APP_PATH=$("$REPO/Install/wrap-as-app.sh" "$EXEC_PATH" "com.local.snappy-nest" "$STAGE_DIR" "TouchbarPet")
echo "==> staged at $APP_PATH"

# ---- 4. install to /Applications -------------------------------------------

DEST="/Applications/TouchbarPet.app"
if [ -e "$DEST" ]; then
    printf "==> %s already exists. Overwrite? [y/N] " "$DEST"
    read -r reply
    case "$reply" in
        y|Y) rm -rf "$DEST" ;;
        *) echo "aborted."; exit 1 ;;
    esac
fi
cp -R "$APP_PATH" "$DEST"

# ---- 5. summary ------------------------------------------------------------

cat <<EOF

✅ Installed to $DEST

Getting started:
  * Launch from Spotlight or the Applications folder
  * The 🐾 menu bar icon opens the app menu
  * Escape hatch: press Opt+Cmd+\\ to reclaim the default Touch Bar
  * README.md: $REPO/README.md

macOS may ask to allow Automation for Spotify on first playback; accept the
prompt to enable position/duration/play-pause. Deny → the Spotify adapter
reports unavailable and the browser adapter is used instead.
EOF
