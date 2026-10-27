#!/bin/sh
# test_binary.sh - check a lizard program binary, whatever built it
#
# Usage:  tests/test_binary.sh <path-to-lizard> [<path-to-datagen>]
#
# This is the gate for the binaries attached to a release: it builds nothing and
# needs nothing but the program (and, when it is available, datagen to make the
# samples).  It covers the compression levels, the block sizes, the frame
# options, stdin/stdout, multiple files and the failure cases, and checks the
# decompressed bytes every time instead of trusting the exit code alone.
#
# When a check fails the output of the command is printed, so a failure in CI
# can be understood without reproducing it on the platform.
#
# On Windows run it from Git Bash; paths with backslashes are accepted.

set -u

BIN=${1:-}
if [ -z "$BIN" ] || [ ! -f "$BIN" ]; then
    echo "usage: $0 <path-to-lizard> [<path-to-datagen>]" >&2
    exit 2
fi
DATAGEN=${2:-}

case $BIN in
    /*|?:/*) ;;                 # absolute, or C:/...
    *) BIN=$(cd "$(dirname "$BIN")" && pwd)/$(basename "$BIN") ;;
esac

WORK=$(mktemp -d "${TMPDIR:-/tmp}/lizard-cli.XXXXXX") || exit 2
trap 'rm -rf "$WORK"' EXIT INT TERM

LOG=$WORK/log
fail=0
checks=0

# The binary may need a runner: a *.exe is a Windows program, and an aarch64
# ELF runs under qemu on an x86 host.
runner_for() {
    case $1 in
        *.exe|*.EXE) echo wine ;;
        *)
            # An aarch64 binary needs qemu only when it cannot run natively.
            case $(uname -m) in
                aarch64|arm64) ;;
                *)
                    if command -v file >/dev/null 2>&1 && file -b "$1" 2>/dev/null | grep -qi 'ARM aarch64'; then
                        if command -v qemu-aarch64 >/dev/null 2>&1; then
                            echo "qemu-aarch64 -L /usr/aarch64-linux-gnu"
                        else
                            echo "qemu-aarch64-static -L /usr/aarch64-linux-gnu"
                        fi
                    fi
                    ;;
            esac
            ;;
    esac
}

run_bin() { # binary args... (no redirection of its output)
    _bin=$1; shift
    _runner=$(runner_for "$_bin")
    if [ -n "$_runner" ]; then
        $_runner "$_bin" "$@"
    else
        "$_bin" "$@"
    fi
}

run()  { run_bin "$@" >"$LOG" 2>&1; }
ok()   { checks=$((checks + 1)); }
bad()  {
    checks=$((checks + 1)); fail=$((fail + 1))
    echo "FAIL: $*"
    if [ -s "$LOG" ]; then sed 's/^/    | /' "$LOG" | head -6; fi
}
dump() { # show the first bytes of a file, for a compressed sample that fails
    if [ -f "$1" ]; then
        echo "    file: $(wc -c < "$1" | tr -d ' ') bytes"
        od -An -tx1 -N48 "$1" 2>/dev/null | head -3 | sed 's/^/    hex: /'
    fi
}

same() { # file file
    if command -v sha256sum >/dev/null 2>&1; then
        [ "$(sha256sum "$1" | cut -d' ' -f1)" = "$(sha256sum "$2" | cut -d' ' -f1)" ]
    elif command -v shasum >/dev/null 2>&1; then
        [ "$(shasum -a 256 "$1" | cut -d' ' -f1)" = "$(shasum -a 256 "$2" | cut -d' ' -f1)" ]
    else
        cmp -s "$1" "$2"
    fi
}

# --- samples ---------------------------------------------------------------
if [ -n "$DATAGEN" ]; then
    # datagen may be a Windows program too, so it goes through the runner
    run_bin "$DATAGEN" -s1 -g256KB > "$WORK/text" 2>/dev/null
    run_bin "$DATAGEN" -s2 -g64KB -P0 > "$WORK/random" 2>/dev/null
    run_bin "$DATAGEN" -s3 -g1M -P99 > "$WORK/repetitive" 2>/dev/null
else
    printf 'the quick brown fox jumps over the lazy dog\n%.0s' $(seq 1 5000) > "$WORK/text"
    : > "$WORK/random"
    cp "$WORK/text" "$WORK/repetitive"
fi
: > "$WORK/empty"
printf 'x' > "$WORK/one-byte"

echo "binary: $BIN"
echo "version: $(run_bin "$BIN" -V 2>&1 | head -1)"

# --- version and help ------------------------------------------------------
run "$BIN" -V;        [ $? -eq 0 ] && ok || bad "-V failed"
if grep -q '[0-9][0-9]*\.[0-9][0-9]*\.[0-9]' "$LOG"; then ok; else bad "-V does not print a version"; fi
run "$BIN" -h;        [ $? -eq 0 ] && ok || bad "-h failed"

# --- every compression level ----------------------------------------------
for lvl in $(seq 10 49); do
    rm -f "$WORK/t.liz" "$WORK/t.out"
    if ! run "$BIN" -"$lvl" -f "$WORK/text" "$WORK/t.liz"; then
        bad "compression at level -$lvl"; continue
    fi
    ok
    if ! run "$BIN" -t "$WORK/t.liz"; then
        bad "integrity test at level -$lvl"; dump "$WORK/t.liz"; continue
    fi
    ok
    if ! run "$BIN" -d -f "$WORK/t.liz" "$WORK/t.out"; then
        bad "decompression at level -$lvl"; dump "$WORK/t.liz"; continue
    fi
    ok
    if same "$WORK/text" "$WORK/t.out"; then ok; else bad "round-trip at level -$lvl"; fi
done

# --- block sizes -----------------------------------------------------------
for bs in 1 2 3 4 5 6 7; do
    for lvl in 20 40; do
        rm -f "$WORK/b.liz" "$WORK/b.out"
        if ! run "$BIN" -"$lvl" -B"$bs" -f "$WORK/repetitive" "$WORK/b.liz"; then
            bad "compression at level -$lvl -B$bs"; continue
        fi
        ok
        if ! run "$BIN" -d -f "$WORK/b.liz" "$WORK/b.out"; then
            bad "decompression at level -$lvl -B$bs"; dump "$WORK/b.liz"; continue
        fi
        ok
        if same "$WORK/repetitive" "$WORK/b.out"; then ok; else bad "round-trip at level -$lvl -B$bs"; fi
    done
done

# --- linked blocks and frame options --------------------------------------
for opts in "-BD" "--content-size" "--no-frame-crc" "--content-size -BD"; do
    rm -f "$WORK/f.liz" "$WORK/f.out"
    # shellcheck disable=SC2086
    if ! run "$BIN" -29 $opts -f "$WORK/text" "$WORK/f.liz"; then
        bad "compression with $opts"; continue
    fi
    ok
    if ! run "$BIN" -d -f "$WORK/f.liz" "$WORK/f.out"; then
        bad "decompression with $opts"; dump "$WORK/f.liz"; continue
    fi
    ok
    if same "$WORK/text" "$WORK/f.out"; then ok; else bad "round-trip with $opts"; fi
done

# --- tiny and empty inputs -------------------------------------------------
for sample in empty one-byte; do
    rm -f "$WORK/s.liz" "$WORK/s.out"
    if ! run "$BIN" -19 -f "$WORK/$sample" "$WORK/s.liz"; then
        bad "compression of $sample"; continue
    fi
    ok
    if ! run "$BIN" -d -f "$WORK/s.liz" "$WORK/s.out"; then
        bad "decompression of $sample"; dump "$WORK/s.liz"; continue
    fi
    ok
    if same "$WORK/$sample" "$WORK/s.out"; then ok; else bad "round-trip of $sample"; fi
done

# --- stdin / stdout --------------------------------------------------------
rm -f "$WORK/p.liz" "$WORK/p.out"
if run_bin "$BIN" -19 < "$WORK/text" > "$WORK/p.liz" 2>/dev/null; then ok; else bad "stdin to stdout"; fi
run "$BIN" -t "$WORK/p.liz"; [ $? -eq 0 ] && ok || bad "integrity test of the stdin stream"
if run_bin "$BIN" -d -c "$WORK/p.liz" > "$WORK/p.out" 2>/dev/null; then ok; else bad "-d -c"; fi
if same "$WORK/text" "$WORK/p.out"; then ok; else bad "stdin/stdout round-trip"; fi

# --- multiple files --------------------------------------------------------
mkdir -p "$WORK/multi"
cp "$WORK/text" "$WORK/multi/text"
cp "$WORK/random" "$WORK/multi/random"
( cd "$WORK/multi" && run_bin "$BIN" -19 -f -m text random > /dev/null 2>&1 ); rc=$?
[ "$rc" -eq 0 ] && ok || bad "-m compression"
( cd "$WORK/multi" && run_bin "$BIN" -d -f -m text.liz random.liz > "$LOG" 2>&1 ); rc=$?
if [ "$rc" -eq 0 ]; then ok; else bad "-m decompression"; dump "$WORK/multi/random.liz"; fi
if same "$WORK/multi/text" "$WORK/text" && same "$WORK/multi/random" "$WORK/random"; then
    ok
else
    bad "-m changed the decompressed bytes"
fi

# --- failure cases ---------------------------------------------------------
run "$BIN" -d "$WORK/text"; [ $? -ne 0 ] && ok || bad "decompressing a non-lizard file succeeded"
run "$BIN" "$WORK/does-not-exist"; [ $? -ne 0 ] && ok || bad "compressing a missing file succeeded"
run "$BIN" -t "$WORK/does-not-exist"; [ $? -ne 0 ] && ok || bad "testing a missing file succeeded"

# a single flipped byte in the payload must be caught by the frame checksum
rm -f "$WORK/c.liz"
run "$BIN" -19 -f "$WORK/text" "$WORK/c.liz"
size=$(wc -c < "$WORK/c.liz" | tr -d ' ')
if [ "$size" -gt 16 ]; then
    offset=$((size / 2))
    printf '\377' | dd of="$WORK/c.liz" bs=1 seek="$offset" conv=notrunc >/dev/null 2>&1
    run "$BIN" -t "$WORK/c.liz"
    [ $? -ne 0 ] && ok || bad "a corrupted stream passed -t"
else
    bad "compressed sample too small to corrupt"
fi

# --- result ----------------------------------------------------------------
echo
if [ "$fail" -ne 0 ]; then
    echo "FAILED: $fail of $checks checks"
    exit 1
fi
echo "OK: $checks checks"
