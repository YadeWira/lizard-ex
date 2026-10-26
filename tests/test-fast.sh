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

# LIZARD_QUICK=1 keeps the suite bounded for the sanitizer jobs, where every
# case costs five to ten times more than in a plain build.
QUICK=${LIZARD_QUICK:-0}
if [ "$QUICK" = 1 ]; then
    FRAMETEST_ITER=32
    FUZZER_TIME=10s
else
    FRAMETEST_ITER=256
    FUZZER_TIME=20s
fi

echo "== test tools =="
make native

echo
echo "== fullbench (one pass over the frame code) =="
./fullbench --no-prompt -i1 "$ROOT/lib/lizard_frame.c"

echo
echo "== frametest ($FRAMETEST_ITER iterations) =="
./frametest -i"$FRAMETEST_ITER"

echo
echo "== fuzzer ($FUZZER_TIME) =="
./fuzzer --no-prompt -T"$FUZZER_TIME"

echo
echo "== command line (bounded cases) =="
if [ "$QUICK" = 1 ]; then
    # test-lizard-basic pushes 256 MB through several levels; under the
    # sanitizers that dominates the whole run, so a smaller round-trip of the
    # same paths replaces it.
    ./datagen -g8M -P50 > tmp.quick
    ../programs/lizard -19 -f tmp.quick tmp.quick.liz
    ../programs/lizard -t tmp.quick.liz
    ../programs/lizard -d -f tmp.quick.liz tmp.quick.out
    cmp tmp.quick tmp.quick.out
    rm -f tmp.quick tmp.quick.liz tmp.quick.out
    make test-lizard-multiple test-lizard-sparse \
         test-lizard-frame-concatenation test-lizard-testmode
else
    make test-lizard-basic test-lizard-multiple test-lizard-sparse \
         test-lizard-frame-concatenation test-lizard-testmode
fi

echo
echo "fast suite: OK"
