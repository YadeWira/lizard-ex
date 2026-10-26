#!/bin/sh
# test_interop.sh - cross-build interoperability test for Lizard
#
# Usage:  tests/test_interop.sh <binary> [<binary> ...]
#
# Every binary is run on the same deterministic corpus at every compression
# level, and every stream produced by one binary must decode, byte for byte,
# with every other binary.  On top of that, builds that agree on the pointer
# width must produce identical streams: the encoder must not depend on the
# compiler, the OS or the CPU, only on the word size it was built for.
#
# The runner is picked from the binary itself:
#   *.exe                -> wine
#   ELF ... ARM aarch64  -> qemu-aarch64 (with -L <sysroot> when it exists)
#   anything else        -> executed natively
#
# Environment:
#   LIZARD_INTEROP_LEVELS     levels to sweep (default: 10 11 ... 49)
#   LIZARD_INTEROP_KEEP=1     keep the temporary directory
#   QEMU_AARCH64              override the qemu-aarch64 command line
#
# Exit status is 0 only when every stream decodes everywhere and every
# same-width build produced the same bytes.

set -u

ROOT=$(cd "$(dirname "$0")/.." && pwd)
TMPD=$(mktemp -d "${TMPDIR:-/tmp}/lizard-interop.XXXXXX") || { echo "error: cannot create a temporary directory" >&2; exit 1; }
trap 'if [ "${LIZARD_INTEROP_KEEP:-0}" = 1 ]; then echo "kept: $TMPD"; else rm -rf "$TMPD"; fi' EXIT INT TERM

if [ "$#" -eq 0 ]; then
    echo "usage: $0 <binary> [<binary> ...]" >&2
    exit 2
fi

# --- helpers ---------------------------------------------------------------

bin_name() { basename "$1"; }

runner_for() {
    bin=$1
    r=""
    case $bin in
        *.exe|*.EXE) r="wine" ;;
    esac
    if [ -z "$r" ] && command -v file >/dev/null 2>&1; then
        if file -b "$bin" 2>/dev/null | grep -qi 'ARM aarch64'; then
            r=${QEMU_AARCH64:-"qemu-aarch64 -L /usr/aarch64-linux-gnu"}
        fi
    fi
    printf '%s' "$r"
}

width_for() {
    if command -v file >/dev/null 2>&1; then
        case $(file -b "$1" 2>/dev/null) in
            *"ELF 32-bit"*|*"PE32 executable"*) echo 32; return ;;
            *"ELF 64-bit"*|*"PE32+ executable"*) echo 64; return ;;
        esac
    fi
    echo unknown
}

run_bin() { # binary args...
    _bin=$1; shift
    _runner=$(runner_for "$_bin")
    if [ -n "$_runner" ]; then
        $_runner "$_bin" "$@"
    else
        "$_bin" "$@"
    fi
}

sum() { # file -> checksum without the trailing name
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$1" | cut -d' ' -f1
    else
        shasum -a 256 "$1" | cut -d' ' -f1
    fi
}

# --- corpus ----------------------------------------------------------------
# Deterministic and independent of the platform: repository sources (text),
# random bytes (incompressible, exercises stored blocks) and a mix of both
# (exercises match finders at different entropy levels).

make_corpus() {
    dir=$1
    cat "$ROOT"/lib/*.c "$ROOT"/lib/*.h > "$dir/text" 2>/dev/null
    python3 - "$dir" <<'PY'
import random, sys
d = sys.argv[1]
r = random.Random(0x11A2D)
with open(d + "/rand", "wb") as f:
    f.write(r.randbytes(512 * 1024))
with open(d + "/mixed", "wb") as f:
    chunk = r.randbytes(4096)
    for i in range(64):
        f.write(chunk * (i % 3 + 1))
        f.write(r.randbytes(1024))
PY
    cat "$dir/text" "$dir/rand" "$dir/mixed" > "$dir/corpus"
}

make_corpus "$TMPD"
CORPUS=$TMPD/corpus
CORPUS_SUM=$(sum "$CORPUS")
CORPUS_SIZE=$(wc -c < "$CORPUS" | tr -d ' ')

# --- preflight -------------------------------------------------------------

BINS=""
for b in "$@"; do
    if [ ! -f "$b" ]; then
        echo "error: no such file: $b" >&2
        exit 2
    fi
    if [ -z "$(runner_for "$b")" ] && [ ! -x "$b" ]; then
        echo "error: not executable: $b" >&2
        exit 2
    fi
    if [ ! -f "$TMPD/probe.$(bin_name "$b")" ]; then
        # A one byte round-trip proves the binary can actually run here.
        printf 'x' > "$TMPD/one"
        if ! run_bin "$b" -q -c "$TMPD/one" >/dev/null 2>&1; then
            echo "error: cannot run $b on this host (missing runner or incompatible libc)" >&2
            exit 2
        fi
        : > "$TMPD/probe.$(bin_name "$b")"
    fi
    BINS="$BINS $b"
done

platform_for() {
    case $1 in
        *.exe|*.EXE) echo windows ;;
        *)
            if command -v file >/dev/null 2>&1 && file -b "$1" 2>/dev/null | grep -qi 'ARM aarch64'; then
                echo arm64
            else
                echo native
            fi
            ;;
    esac
}

echo "corpus: $CORPUS_SIZE bytes (sha256 $CORPUS_SUM)"
for b in $BINS; do
    printf '  %-24s %-8s %s-bit\n' "$(bin_name "$b")" "$(platform_for "$b")" "$(width_for "$b")"
done

# --- compression level sweep ----------------------------------------------

levels=${LIZARD_INTEROP_LEVELS:-$(seq 10 49)}
fail=0
checked=0

echo
echo "== level sweep =="
for lvl in $levels; do
    for b in $BINS; do
        out=$TMPD/stream."$(bin_name "$b")"
        rm -f "$out"
        if ! run_bin "$b" -"$lvl" -q -f "$CORPUS" "$out" >/dev/null 2>&1; then
            echo "FAIL: $(bin_name "$b") failed to compress level -$lvl"
            fail=$((fail + 1))
            continue
        fi
        echo "$(sum "$out") $lvl $(bin_name "$b")" >> "$TMPD/streams.$lvl"
    done

    # same pointer width => same bytes
    for w in 32 64; do
        ref=""
        for b in $BINS; do
            [ "$(width_for "$b")" = "$w" ] || continue
            s=$(awk -v n="$(bin_name "$b")" '$3 == n { print $1 }' "$TMPD/streams.$lvl" 2>/dev/null | head -1)
            [ -n "$s" ] || continue
            if [ -z "$ref" ]; then
                ref=$s; refname=$(bin_name "$b")
            elif [ "$s" != "$ref" ]; then
                echo "FAIL: level -$lvl: $(bin_name "$b") ($w-bit) produced different bytes than $refname"
                fail=$((fail + 1))
            fi
        done
    done

    # every stream decodes with every binary
    for b in $BINS; do
        stream=$TMPD/stream."$(bin_name "$b")"
        [ -f "$stream" ] || continue
        for d in $BINS; do
            rm -f "$TMPD/decoded"
            if ! run_bin "$d" -d -q -f "$stream" "$TMPD/decoded" >/dev/null 2>&1; then
                echo "FAIL: level -$lvl: $(bin_name "$d") cannot decode the stream of $(bin_name "$b")"
                fail=$((fail + 1))
                continue
            fi
            if [ "$(sum "$TMPD/decoded")" != "$CORPUS_SUM" ]; then
                echo "FAIL: level -$lvl: $(bin_name "$d") decoded wrong bytes from $(bin_name "$b")"
                fail=$((fail + 1))
            fi
            checked=$((checked + 1))
        done
    done
    rm -f "$TMPD"/streams."$lvl"
done
echo "decodes checked: $checked"

# --- block size sweep ------------------------------------------------------
# The offset width depends on the block size, so block sizes above the 32-bit
# window (B5, B6, B7) are the ones that break between builds when they break.

echo
echo "== block size sweep =="
for lvl in 10 20 30 40; do
    for bs in 1 2 3 4 5 6 7; do
        for b in $BINS; do
            out=$TMPD/bs."$(bin_name "$b")"
            rm -f "$out"
            if ! run_bin "$b" -"$lvl" -B"$bs" -q -f "$CORPUS" "$out" >/dev/null 2>&1; then
                echo "FAIL: $(bin_name "$b") failed level -$lvl -B$bs"
                fail=$((fail + 1))
                continue
            fi
            for d in $BINS; do
                rm -f "$TMPD/decoded"
                if ! run_bin "$d" -d -q -f "$out" "$TMPD/decoded" >/dev/null 2>&1; then
                    echo "FAIL: level -$lvl -B$bs: $(bin_name "$d") cannot decode the stream of $(bin_name "$b")"
                    fail=$((fail + 1))
                    continue
                fi
                if [ "$(sum "$TMPD/decoded")" != "$CORPUS_SUM" ]; then
                    echo "FAIL: level -$lvl -B$bs: $(bin_name "$d") decoded wrong bytes from $(bin_name "$b")"
                    fail=$((fail + 1))
                fi
                checked=$((checked + 1))
            done
        done
    done
done

echo
if [ "$fail" -ne 0 ]; then
    echo "FAILED: $fail interoperability failure(s)"
    exit 1
fi
echo "OK: $(echo $BINS | wc -w | tr -d ' ') builds, $checked decodes, all streams portable"
