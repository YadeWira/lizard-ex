#!/bin/sh
# build-matrix.sh - build Lizard for every target whose toolchain is installed
#
# Usage:  tests/build-matrix.sh [output-dir]
#
# On a Linux host this produces the binaries the interoperability test needs:
#
#   linux-x64     native gcc
#   linux-i386    native gcc -m32            (needs gcc-multilib)
#   linux-arm64   aarch64-linux-gnu-gcc      (needs gcc-aarch64-linux-gnu)
#   win-x64       x86_64-w64-mingw32-gcc     (needs mingw-w64)
#   win-x86       i686-w64-mingw32-gcc       (needs mingw-w64)
#
# Targets whose toolchain is missing are skipped with a notice, so the script
# also works on a plain developer machine.  A target that has its toolchain
# but does not build is an error.
#
# The builds happen in a throw-away copy of the tree: nothing is written to
# the working directory except the output directory.

set -u

ROOT=$(cd "$(dirname "$0")/.." && pwd)
OUT=${1:-$ROOT/build-matrix}
WORK=$(mktemp -d "${TMPDIR:-/tmp}/lizard-matrix.XXXXXX") || exit 2
trap 'rm -rf "$WORK"' EXIT INT TERM

mkdir -p "$OUT"

toolchain_ok() { # compiler command line
    printf 'int main(void){return 0;}' > "$WORK/probe.c" 2>/dev/null || return 1
    $1 "$WORK/probe.c" -o "$WORK/probe.bin" >/dev/null 2>&1
}

build() { # name compiler extension
    name=$1; cc=$2; ext=$3
    rm -rf "$WORK/tree"
    cp -a "$ROOT" "$WORK/tree" || return 1
    if ( cd "$WORK/tree/programs" && make lizard CC="$cc" ) >"$WORK/log" 2>&1; then
        cp "$WORK/tree/programs/lizard$ext" "$OUT/$name$ext" || return 1
        printf '  %-12s %s\n' "$name" "$($cc --version 2>/dev/null | head -1)"
        return 0
    fi
    echo "  $name: BUILD FAILED"
    tail -20 "$WORK/log" | sed 's/^/    /'
    return 1
}

failed=0
for t in linux-x64 linux-i386 linux-arm64 win-x64 win-x86; do
    case $t in
        linux-x64)   cc=gcc;                   ext="" ;;
        linux-i386)  cc="gcc -m32";            ext="" ;;
        linux-arm64) cc=aarch64-linux-gnu-gcc; ext="" ;;
        win-x64)     cc=x86_64-w64-mingw32-gcc; ext=".exe" ;;
        win-x86)     cc=i686-w64-mingw32-gcc;   ext=".exe" ;;
    esac
    if ! toolchain_ok "$cc"; then
        echo "  $t: skipped (toolchain not found: $cc)"
        continue
    fi
    build "$t" "$cc" "$ext" || failed=$((failed + 1))
done

echo "binaries in $OUT"
[ "$failed" -eq 0 ] || { echo "$failed target(s) failed to build" >&2; exit 1; }
