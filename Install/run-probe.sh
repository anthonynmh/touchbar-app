#!/bin/bash
# run-probe.sh <NN>
#
# Builds the probe executable, wraps it in a minimal .app bundle (probes 01/02
# only, since those exercise Touch Bar APIs that need real activation), and
# prints the captured stderr — which is where the probes NSLog their results.
#
#   ./Install/run-probe.sh 01   # Touch Bar render + bounds
#   ./Install/run-probe.sh 02   # Persistent presenter (DFR)
#   ./Install/run-probe.sh 03   # Brightness (DisplayServices)
#   ./Install/run-probe.sh 04   # Volume (Core Audio)
#   ./Install/run-probe.sh 05   # Spotify + MediaRemote

set -euo pipefail

if [ $# -ne 1 ]; then
    echo "usage: $0 <NN>" >&2
    exit 2
fi

REPO="$(cd "$(dirname "$0")/.." && pwd)"
NN="$1"

case "$NN" in
    01) TARGET="Probe01TouchBar";   NEEDS_BUNDLE=1; WAIT_SECS=15 ;;
    02) TARGET="Probe02Presenter";  NEEDS_BUNDLE=1; WAIT_SECS=20 ;;
    03) TARGET="Probe03Brightness"; NEEDS_BUNDLE=0; WAIT_SECS=3  ;;
    04) TARGET="Probe04Volume";     NEEDS_BUNDLE=0; WAIT_SECS=3  ;;
    05) TARGET="Probe05Media";      NEEDS_BUNDLE=0; WAIT_SECS=8  ;;
    *)  echo "error: unknown probe number '$NN'" >&2; exit 2 ;;
esac

echo "Building $TARGET..." >&2
cd "$REPO"
swift build --product "$TARGET" >&2

EXEC_PATH="$REPO/.build/debug/$TARGET"
if [ ! -x "$EXEC_PATH" ]; then
    echo "error: no executable produced at $EXEC_PATH" >&2
    exit 1
fi

if [ "$NEEDS_BUNDLE" = "1" ]; then
    APP_PATH=$("$REPO/Install/wrap-as-app.sh" \
        "$EXEC_PATH" \
        "com.local.snappy-nest.probe$NN" \
        /tmp/snappy-probes \
        "$TARGET")
    LOG_FILE="/tmp/snappy-probes/${TARGET}.stderr"
    : > "$LOG_FILE"
    open -Wn --stderr "$LOG_FILE" "$APP_PATH" &
    OPEN_PID=$!
    sleep "$WAIT_SECS"
    kill "$OPEN_PID" 2>/dev/null || true
    wait "$OPEN_PID" 2>/dev/null || true
    cat "$LOG_FILE"
else
    "$EXEC_PATH"
fi
