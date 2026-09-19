#!/bin/bash
# run-probe.sh <NN> [--write] [--allow-unmute]
#
# Builds the probe executable, wraps it in a minimal .app bundle (probes 01/02
# only, since those exercise Touch Bar APIs that need real activation), and
# prints the captured stderr — which is where the probes NSLog their results.
#
#   ./Install/run-probe.sh 01   # Touch Bar render + bounds
#   ./Install/run-probe.sh 02   # Persistent presenter (DFR)
#   ./Install/run-probe.sh 03   # Brightness read-only (DisplayServices)
#   ./Install/run-probe.sh 04   # Volume read-only (Core Audio)
#   ./Install/run-probe.sh 03 --write
#   ./Install/run-probe.sh 04 --write [--allow-unmute]
#   ./Install/run-probe.sh 05   # Spotify + MediaRemote (in-process and perl-hosted)

set -euo pipefail

if [ $# -lt 1 ]; then
    echo "usage: $0 <NN> [--write] [--allow-unmute]" >&2
    exit 2
fi

REPO="$(cd "$(dirname "$0")/.." && pwd)"
NN="$1"
shift

case "$NN" in
    01) TARGET="Probe01TouchBar";   NEEDS_BUNDLE=1; WAIT_SECS=15 ;;
    02) TARGET="Probe02Presenter";  NEEDS_BUNDLE=1; WAIT_SECS=20 ;;
    03) TARGET="Probe03Brightness"; NEEDS_BUNDLE=0; WAIT_SECS=3  ;;
    04) TARGET="Probe04Volume";     NEEDS_BUNDLE=0; WAIT_SECS=3  ;;
    05) TARGET="Probe05Media";      NEEDS_BUNDLE=0; WAIT_SECS=8  ;;
    *)  echo "error: unknown probe number '$NN'" >&2; exit 2 ;;
esac

WRITE=0
ALLOW_UNMUTE=0
PROBE_ARGS=()
for argument in "$@"; do
    case "$argument" in
        --write)
            [ "$WRITE" = "0" ] || { echo "error: duplicate --write" >&2; exit 2; }
            WRITE=1
            PROBE_ARGS+=("$argument")
            ;;
        --allow-unmute)
            [ "$ALLOW_UNMUTE" = "0" ] || { echo "error: duplicate --allow-unmute" >&2; exit 2; }
            ALLOW_UNMUTE=1
            PROBE_ARGS+=("$argument")
            ;;
        *) echo "error: unknown flag '$argument'" >&2; exit 2 ;;
    esac
done

case "$NN" in
    03)
        if [ "$ALLOW_UNMUTE" = "1" ]; then
            echo "error: --allow-unmute is valid only for Probe 04" >&2
            exit 2
        fi
        ;;
    04)
        if [ "$ALLOW_UNMUTE" = "1" ] && [ "$WRITE" != "1" ]; then
            echo "error: --allow-unmute requires --write" >&2
            exit 2
        fi
        ;;
    *)
        if [ "${#PROBE_ARGS[@]}" -ne 0 ]; then
            echo "error: write flags are valid only for Probes 03 and 04" >&2
            exit 2
        fi
        ;;
esac

echo "Building $TARGET..." >&2
cd "$REPO"
swift build --product "$TARGET" >&2

EXEC_PATH="$REPO/.build/debug/$TARGET"
if [ ! -x "$EXEC_PATH" ]; then
    echo "error: no executable produced at $EXEC_PATH" >&2
    exit 1
fi

# Probe 05c loads the MediaRemote host dylib into /usr/bin/perl.
if [ "$NN" = "05" ]; then
    echo "Building SnappyMediaRemoteHost..." >&2
    swift build --product SnappyMediaRemoteHost >&2
    HOST_DYLIB="$REPO/.build/debug/libSnappyMediaRemoteHost.dylib"
    if [ ! -f "$HOST_DYLIB" ] || [ -L "$HOST_DYLIB" ]; then
        echo "error: no host dylib produced at $HOST_DYLIB" >&2
        exit 1
    fi
    export SNAPPY_MEDIAREMOTE_HOST="$HOST_DYLIB"
fi

if [ "$NEEDS_BUNDLE" = "1" ]; then
    umask 077
    TEMP_BASE="${TMPDIR:-/tmp}"
    if [ ! -d "$TEMP_BASE" ] || [ -L "$TEMP_BASE" ]; then
        echo "error: probe temporary parent is not a safe directory: $TEMP_BASE" >&2
        exit 1
    fi
    TEMP_BASE=$(cd -P "$TEMP_BASE" && pwd)
    TEMP_DIR=$(mktemp -d "${TEMP_BASE%/}/snappy-probes.XXXXXX")
    APP_PID=""
    OPEN_PID=""
    terminate_probe_app() {
        [ -n "$APP_PID" ] || return 0
        kill "$APP_PID" 2>/dev/null || true
        for _ in {1..50}; do
            kill -0 "$APP_PID" 2>/dev/null || break
            sleep 0.1
        done
        if kill -0 "$APP_PID" 2>/dev/null; then
            kill -KILL "$APP_PID" 2>/dev/null || true
        fi
        APP_PID=""
    }
    cleanup() {
        terminate_probe_app
        if [ -n "$OPEN_PID" ]; then
            kill "$OPEN_PID" 2>/dev/null || true
            wait "$OPEN_PID" 2>/dev/null || true
        fi
        case "$TEMP_DIR" in
            "${TEMP_BASE%/}"/snappy-probes.*)
                if [ -d "$TEMP_DIR" ] && [ ! -L "$TEMP_DIR" ]; then
                    rm -rf -- "$TEMP_DIR"
                fi
                ;;
            *) echo "warning: refusing unexpected probe cleanup path: $TEMP_DIR" >&2 ;;
        esac
    }
    interrupted() {
        trap - EXIT HUP INT TERM
        cleanup
        exit 130
    }
    trap cleanup EXIT
    trap interrupted HUP INT TERM

    if [ "$(stat -f '%Lp' "$TEMP_DIR")" != "700" ]; then
        echo "error: probe temporary directory is not private: $TEMP_DIR" >&2
        exit 1
    fi
    APP_PATH=$("$REPO/Install/wrap-as-app.sh" \
        "$EXEC_PATH" \
        "com.local.snappy-nest.probe$NN" \
        "$TEMP_DIR" \
        "$TARGET")
    LOG_FILE="$TEMP_DIR/${TARGET}.stderr"
    PID_FILE="$TEMP_DIR/${TARGET}.pid"
    : > "$LOG_FILE"
    open -Wn --stderr "$LOG_FILE" "$APP_PATH" \
        --args --snappy-pid-file "$PID_FILE" &
    OPEN_PID=$!

    for _ in {1..100}; do
        if [ -f "$PID_FILE" ]; then
            read -r APP_PID < "$PID_FILE" || APP_PID=""
            case "$APP_PID" in
                ''|*[!0-9]*) APP_PID="" ;;
                *) kill -0 "$APP_PID" 2>/dev/null && break || APP_PID="" ;;
            esac
        fi
        kill -0 "$OPEN_PID" 2>/dev/null || break
        sleep 0.1
    done
    if [ -z "$APP_PID" ]; then
        echo "error: could not identify the launched probe application" >&2
        exit 1
    fi

    sleep "$WAIT_SECS"
    terminate_probe_app
    wait "$OPEN_PID" 2>/dev/null || true
    OPEN_PID=""
    cat "$LOG_FILE"
else
    "$EXEC_PATH" ${PROBE_ARGS[@]+"${PROBE_ARGS[@]}"}
fi
