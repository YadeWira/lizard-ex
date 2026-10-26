#!/bin/sh
# test-fast.sh - bounded regression suite
#
# Runs the parts of the test suite that finish in a few minutes on any
# machine.  The multi-gigabyte cases (test-lizard-hugefile, the 3 GB part of
# test-lizard-contentSize) are deliberately left out; run "make test" for
# those.
#
# Usage:  tests/test-fast.sh        (or: make test-fast)
#
# CC, CFLAGS and MOREFLAGS are passed through to the Makefiles, so the same
# script covers the plain build, -Werror builds and the sanitizer builds.

set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT/tests"

echo "== test tools =="
make native

echo
echo "== fullbench (one pass over the frame code) =="
./fullbench --no-prompt -i1 "$ROOT/lib/lizard_frame.c"

echo
echo "== frametest (256 iterations) =="
./frametest -i256

echo
echo "== fuzzer (20 seconds) =="
./fuzzer --no-prompt -T20s

echo
echo "== command line (bounded cases) =="
make test-lizard-basic test-lizard-multiple test-lizard-sparse \
     test-lizard-frame-concatenation test-lizard-testmode

echo
echo "fast suite: OK"
