#!/bin/bash
# Remove only this repository's generated build directories.

set -euo pipefail

if [ "$#" -ne 0 ]; then
    echo "usage: $0" >&2
    exit 2
fi

case "$0" in
    /*) SCRIPT_PATH="$0" ;;
    *) SCRIPT_PATH="$PWD/$0" ;;
esac

if [ -L "$SCRIPT_PATH" ]; then
    echo "error: refusing to run through a symlinked script" >&2
    exit 1
fi

SCRIPT_DIR=$(cd -P "$(dirname "$SCRIPT_PATH")" && pwd)
REPO=$(cd -P "$SCRIPT_DIR/.." && pwd)

reject_symlink_components() {
    local path="$1"
    local remainder component current=""

    case "$path" in
        /*) remainder="${path#/}" ;;
        *) echo "error: internal cleanup path is not absolute: $path" >&2; return 1 ;;
    esac

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
            echo "error: refusing symlinked cleanup path component: $current" >&2
            return 1
        fi
    done
}

reject_symlink_components "$REPO"

TARGETS=(
    "$REPO/.build"
    "$REPO/build/stage"
    "$REPO/dist"
)

# Validate every target before deleting any of them.
for target in "${TARGETS[@]}"; do
    reject_symlink_components "$target"
    if [ -e "$target" ] && [ ! -d "$target" ]; then
        echo "error: cleanup target is not a directory: $target" >&2
        exit 1
    fi
done

for target in "${TARGETS[@]}"; do
    if [ -d "$target" ]; then
        rm -rf -- "$target"
    fi
done
