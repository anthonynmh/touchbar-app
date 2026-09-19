#!/bin/bash

set -euo pipefail

fail() {
    echo "FAIL: $*" >&2
    exit 1
}

expect_failure() {
    if "$@" >/dev/null 2>&1; then
        fail "command unexpectedly succeeded: $*"
    fi
}

TEST_ROOT=$(mktemp -d /private/tmp/snappy-safety-tests.XXXXXX)
cleanup() {
    case "$TEST_ROOT" in
        /private/tmp/snappy-safety-tests.*) rm -rf -- "$TEST_ROOT" ;;
        *) fail "refusing unexpected test cleanup path: $TEST_ROOT" ;;
    esac
}
trap cleanup EXIT HUP INT TERM

SOURCE_ROOT=$(cd "$(dirname "$0")/../.." && pwd -P)

# make clean ignores command-line destination overrides and removes only the
# three repository-owned allowlisted directories.
CLEAN_REPO="$TEST_ROOT/clean-repo"
mkdir -p "$CLEAN_REPO/Install" "$CLEAN_REPO/.build" \
    "$CLEAN_REPO/build/stage" "$CLEAN_REPO/dist"
cp "$SOURCE_ROOT/Makefile" "$CLEAN_REPO/Makefile"
cp "$SOURCE_ROOT/Install/clean.sh" "$CLEAN_REPO/Install/clean.sh"
chmod +x "$CLEAN_REPO/Install/clean.sh"
touch "$CLEAN_REPO/.build/generated" "$CLEAN_REPO/build/stage/generated" \
    "$CLEAN_REPO/dist/generated" "$CLEAN_REPO/sentinel"
mkdir -p "$TEST_ROOT/override-stage" "$TEST_ROOT/override-dist"
touch "$TEST_ROOT/override-stage/sentinel" "$TEST_ROOT/override-dist/sentinel"
make -s -C "$CLEAN_REPO" clean \
    STAGE="$TEST_ROOT/override-stage" \
    DIST="$TEST_ROOT/override-dist" \
    VERSION=unsafe
[ ! -e "$CLEAN_REPO/.build" ] || fail ".build survived clean"
[ ! -e "$CLEAN_REPO/build/stage" ] || fail "build/stage survived clean"
[ ! -e "$CLEAN_REPO/dist" ] || fail "dist survived clean"
[ -f "$CLEAN_REPO/sentinel" ] || fail "repository sentinel was removed"
[ -f "$TEST_ROOT/override-stage/sentinel" ] || fail "STAGE override escaped allowlist"
[ -f "$TEST_ROOT/override-dist/sentinel" ] || fail "DIST override escaped allowlist"

# Validation is all-or-nothing: a symlinked allowlisted target prevents every
# deletion and never follows the link.
mkdir -p "$CLEAN_REPO/.build" "$CLEAN_REPO/build" "$CLEAN_REPO/dist" \
    "$TEST_ROOT/outside-stage"
touch "$CLEAN_REPO/.build/keep" "$CLEAN_REPO/dist/keep" \
    "$TEST_ROOT/outside-stage/sentinel"
ln -s "$TEST_ROOT/outside-stage" "$CLEAN_REPO/build/stage"
expect_failure "$CLEAN_REPO/Install/clean.sh"
[ -f "$CLEAN_REPO/.build/keep" ] || fail "clean deleted before validation completed"
[ -f "$CLEAN_REPO/dist/keep" ] || fail "clean deleted non-symlink target on failure"
[ -f "$TEST_ROOT/outside-stage/sentinel" ] || fail "clean followed target symlink"
expect_failure "$CLEAN_REPO/Install/clean.sh" "$TEST_ROOT/outside-stage"

expect_failure "$SOURCE_ROOT/Install/run-probe.sh" 03 --allow-unmute
expect_failure "$SOURCE_ROOT/Install/run-probe.sh" 04 --allow-unmute
expect_failure "$SOURCE_ROOT/Install/run-probe.sh" 01 --write

# Bundle wrapping accepts only a new app inside a private, non-symlink output
# directory and rejects reuse, traversal, unsafe names, and symlinked paths.
WRAP="$SOURCE_ROOT/Install/wrap-as-app.sh"
EXECUTABLE="$TEST_ROOT/fake-executable"
cp /bin/echo "$EXECUTABLE"
chmod +x "$EXECUTABLE"
OUTPUT="$TEST_ROOT/wrap-output"
mkdir -m 700 "$OUTPUT"
"$WRAP" "$EXECUTABLE" com.local.test "$OUTPUT" TouchbarPet >/dev/null
expect_failure "$WRAP" "$EXECUTABLE" com.local.test "$OUTPUT" TouchbarPet

# The optional host library lands in Contents/Frameworks; symlinks and
# non-dylib files are rejected.
LIBRARY="$TEST_ROOT/libFake.dylib"
: > "$LIBRARY"
LIB_OUTPUT="$TEST_ROOT/lib-output"
mkdir -m 700 "$LIB_OUTPUT"
"$WRAP" "$EXECUTABLE" com.local.test "$LIB_OUTPUT" TouchbarPet "$LIBRARY" >/dev/null
[ -f "$LIB_OUTPUT/TouchbarPet.app/Contents/Frameworks/libFake.dylib" ] || fail "wrap did not bundle the library"
LIB_BAD_OUTPUT="$TEST_ROOT/lib-bad-output"
mkdir -m 700 "$LIB_BAD_OUTPUT"
ln -s "$LIBRARY" "$TEST_ROOT/libLink.dylib"
expect_failure "$WRAP" "$EXECUTABLE" com.local.test "$LIB_BAD_OUTPUT" TouchbarPet "$TEST_ROOT/libLink.dylib"
expect_failure "$WRAP" "$EXECUTABLE" com.local.test "$LIB_BAD_OUTPUT" TouchbarPet "$EXECUTABLE"

SECOND_OUTPUT="$TEST_ROOT/second-output"
mkdir -m 700 "$SECOND_OUTPUT"
expect_failure "$WRAP" "$EXECUTABLE" com.local.test \
    "$TEST_ROOT/second-output/../second-output" TouchbarPet
expect_failure "$WRAP" "$EXECUTABLE" com.local.test "$SECOND_OUTPUT" ../TouchbarPet

SYMLINK_PARENT="$TEST_ROOT/symlink-parent"
mkdir -m 700 "$TEST_ROOT/real-parent"
ln -s "$TEST_ROOT/real-parent" "$SYMLINK_PARENT"
expect_failure "$WRAP" "$EXECUTABLE" com.local.test "$SYMLINK_PARENT" TouchbarPet
ln -s "$TEST_ROOT/outside-stage" "$SECOND_OUTPUT/TouchbarPet.app"
expect_failure "$WRAP" "$EXECUTABLE" com.local.test "$SECOND_OUTPUT" TouchbarPet

# A bundled probe gets a private temporary directory, identifies and terminates
# the launched app process, and removes the directory on exit.
PROBE_REPO="$TEST_ROOT/probe-repo"
FAKE_BIN="$TEST_ROOT/fake-bin"
mkdir -p "$PROBE_REPO/Install" "$FAKE_BIN" "$TEST_ROOT/probe-tmp"
chmod 700 "$TEST_ROOT/probe-tmp"
cp "$SOURCE_ROOT/Install/run-probe.sh" "$PROBE_REPO/Install/run-probe.sh"
cp "$SOURCE_ROOT/Install/wrap-as-app.sh" "$PROBE_REPO/Install/wrap-as-app.sh"
chmod +x "$PROBE_REPO/Install/run-probe.sh" "$PROBE_REPO/Install/wrap-as-app.sh"

cat > "$FAKE_BIN/swift" <<'EOF'
#!/bin/bash
set -eu
target="${@: -1}"
repo=$(pwd -P)
mkdir -p "$repo/.build/debug"
cat > "$repo/.build/debug/$target" <<'APP'
#!/bin/bash
trap 'exit 0' TERM INT
if [ "${1:-}" = "--snappy-pid-file" ]; then
    printf '%s\n' "$$" > "$2"
fi
echo "fake bundled probe running" >&2
while :; do sleep 1; done
APP
chmod +x "$repo/.build/debug/$target"
EOF

cat > "$FAKE_BIN/open" <<'EOF'
#!/bin/bash
set -eu
log=""
app=""
app_args=()
while [ "$#" -gt 0 ]; do
    case "$1" in
        --stderr) log="$2"; shift 2 ;;
        --args) shift; app_args=("$@"); break ;;
        -*) shift ;;
        *) app="$1"; shift ;;
    esac
done
temp_dir=$(dirname "$app")
printf '%s %s\n' "$(stat -f '%Lp' "$temp_dir")" "$temp_dir" > "$PROBE_OBSERVATION"
name=$(basename "$app" .app)
"$app/Contents/MacOS/$name" "${app_args[@]}" 2> "$log" &
wait $!
EOF

cat > "$FAKE_BIN/sleep" <<'EOF'
#!/bin/bash
/bin/sleep 0.05
EOF
chmod +x "$FAKE_BIN/swift" "$FAKE_BIN/open" "$FAKE_BIN/sleep"

PROBE_OBSERVATION="$TEST_ROOT/probe-observation" \
TMPDIR="$TEST_ROOT/probe-tmp" \
PATH="$FAKE_BIN:/usr/bin:/bin:/usr/sbin:/sbin" \
    "$PROBE_REPO/Install/run-probe.sh" 01 >/dev/null
read -r probe_mode probe_temp < "$TEST_ROOT/probe-observation"
[ "$probe_mode" = "700" ] || fail "probe temp mode was $probe_mode, expected 700"
[ ! -e "$probe_temp" ] || fail "probe temp directory survived cleanup"

echo "Shell safety tests passed."
