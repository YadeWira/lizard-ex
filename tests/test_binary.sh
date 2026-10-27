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

fail=0
checks=0

ok()   { checks=$((checks + 1)); }
bad()  { checks=$((checks + 1)); fail=$((fail + 1)); echo "FAIL: $*"; }

same() { # file file
    if command -v sha256sum >/dev/null 2>&1; then
        [ "$(sha256sum "$1" | cut -d' ' -f1)" = "$(sha256sum "$2" | cut -d' ' -f1)" ]
    elif command -v shasum >/dev/null 2>&1; then
        [ "$(shasum -a 256 "$1" | cut -d' ' -f1)" = "$(shasum -a 256 "$2" | cut -d' ' -f1)" ]
    else
        cmp -s "$1" "$2"
    fi
}

expect_ok()   { if "$@" >/dev/null 2>&1; then ok; else bad "expected success: $*"; fi; }
expect_fail() { if "$@" >/dev/null 2>&1; then bad "expected failure: $*"; else ok; fi; }

# --- samples ---------------------------------------------------------------
if [ -n "$DATAGEN" ]; then
    "$DATAGEN" -s1 -g256KB > "$WORK/text" 2>/dev/null
    "$DATAGEN" -s2 -g64KB -P0 > "$WORK/random" 2>/dev/null
    "$DATAGEN" -s3 -g1M -P99 > "$WORK/repetitive" 2>/dev/null
else
    printf 'the quick brown fox jumps over the lazy dog\n%.0s' $(seq 1 5000) > "$WORK/text"
    : > "$WORK/random"
    cp "$WORK/text" "$WORK/repetitive"
fi
: > "$WORK/empty"
printf 'x' > "$WORK/one-byte"

echo "binary: $BIN"
echo "version: $("$BIN" -V 2>&1 | head -1)"

# --- version and help ------------------------------------------------------
expect_ok "$BIN" -V
expect_ok "$BIN" -h
if "$BIN" -V 2>&1 | grep -q '[0-9][0-9]*\.[0-9][0-9]*\.[0-9]'; then ok; else bad "-V does not print a version"; fi

# --- every compression level ----------------------------------------------
for lvl in $(seq 10 49); do
    rm -f "$WORK/t.liz" "$WORK/t.out"
    if ! "$BIN" -"$lvl" -f "$WORK/text" "$WORK/t.liz" >/dev/null 2>&1; then
        bad "compression at level -$lvl"; continue
    fi
    expect_ok "$BIN" -t "$WORK/t.liz"
    if ! "$BIN" -d -f "$WORK/t.liz" "$WORK/t.out" >/dev/null 2>&1; then
        bad "decompression at level -$lvl"; continue
    fi
    if same "$WORK/text" "$WORK/t.out"; then ok; else bad "round-trip at level -$lvl"; fi
done

# --- block sizes -----------------------------------------------------------
for bs in 1 2 3 4 5 6 7; do
    for lvl in 20 40; do
        rm -f "$WORK/b.liz" "$WORK/b.out"
        if ! "$BIN" -"$lvl" -B"$bs" -f "$WORK/repetitive" "$WORK/b.liz" >/dev/null 2>&1; then
            bad "compression at level -$lvl -B$bs"; continue
        fi
        if ! "$BIN" -d -f "$WORK/b.liz" "$WORK/b.out" >/dev/null 2>&1; then
            bad "decompression at level -$lvl -B$bs"; continue
        fi
        if same "$WORK/repetitive" "$WORK/b.out"; then ok; else bad "round-trip at level -$lvl -B$bs"; fi
    done
done

# --- linked blocks and frame options --------------------------------------
for opts in "-BD" "--content-size" "--no-frame-crc" "--content-size -BD"; do
    rm -f "$WORK/f.liz" "$WORK/f.out"
    # shellcheck disable=SC2086
    if ! "$BIN" -29 $opts -f "$WORK/text" "$WORK/f.liz" >/dev/null 2>&1; then
        bad "compression with $opts"; continue
    fi
    if ! "$BIN" -d -f "$WORK/f.liz" "$WORK/f.out" >/dev/null 2>&1; then
        bad "decompression with $opts"; continue
    fi
    if same "$WORK/text" "$WORK/f.out"; then ok; else bad "round-trip with $opts"; fi
done

# --- tiny and empty inputs -------------------------------------------------
for sample in empty one-byte; do
    rm -f "$WORK/s.liz" "$WORK/s.out"
    if ! "$BIN" -19 -f "$WORK/$sample" "$WORK/s.liz" >/dev/null 2>&1; then
        bad "compression of $sample"; continue
    fi
    if ! "$BIN" -d -f "$WORK/s.liz" "$WORK/s.out" >/dev/null 2>&1; then
        bad "decompression of $sample"; continue
    fi
    if same "$WORK/$sample" "$WORK/s.out"; then ok; else bad "round-trip of $sample"; fi
done

# --- stdin / stdout --------------------------------------------------------
rm -f "$WORK/p.liz" "$WORK/p.out"
if "$BIN" -19 < "$WORK/text" > "$WORK/p.liz" 2>/dev/null; then ok; else bad "stdin to stdout"; fi
expect_ok "$BIN" -t "$WORK/p.liz"
if "$BIN" -d -c "$WORK/p.liz" > "$WORK/p.out" 2>/dev/null; then ok; else bad "-d -c"; fi
if same "$WORK/text" "$WORK/p.out"; then ok; else bad "stdin/stdout round-trip"; fi

# --- multiple files --------------------------------------------------------
( cd "$WORK" && "$BIN" -19 -f -m text random >/dev/null 2>&1 ); rc=$?
[ "$rc" -eq 0 ] && ok || bad "-m compression"
( cd "$WORK" && "$BIN" -d -f -m text.liz random.liz >/dev/null 2>&1 ); rc=$?
[ "$rc" -eq 0 ] && ok || bad "-m decompression"
same "$WORK/text" "$WORK/text" && ok || bad "-m lost the input"

# --- failure cases ---------------------------------------------------------
expect_fail "$BIN" -d "$WORK/text"                     # not a lizard stream
expect_fail "$BIN" "$WORK/does-not-exist"
expect_fail "$BIN" -t "$WORK/does-not-exist"

# a single flipped byte in the payload must be caught by the frame checksum
rm -f "$WORK/c.liz"
"$BIN" -19 -f "$WORK/text" "$WORK/c.liz" >/dev/null 2>&1
size=$(wc -c < "$WORK/c.liz" | tr -d ' ')
if [ "$size" -gt 16 ]; then
    offset=$((size / 2))
    printf '\377' | dd of="$WORK/c.liz" bs=1 seek="$offset" conv=notrunc >/dev/null 2>&1
    expect_fail "$BIN" -t "$WORK/c.liz"
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
