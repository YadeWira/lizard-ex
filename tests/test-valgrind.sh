#!/bin/sh
# test-valgrind.sh - bounded memory checker run
#
# Exercises compression, decompression, the frame layer and the fuzzers under
# valgrind.  Only the small cases are used: a valgrind run of the 256 MB or
# 3 GB cases would take hours.
#
# The tree is built with -DLIZARD_RESET_MEM on purpose.  The match finder
# leaves its hash and chain tables uninitialised and relies on bounds checks
# for every value it reads from them (see Lizard_init()); that is deliberate
# and the upstream msan/asan targets do the same.  Without the define, memcheck
# reports those reads and buries anything real.
#
# Usage:  tests/test-valgrind.sh     (or: make test-valgrind)

set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)

CFLAGS="${CFLAGS:--O3} -DLIZARD_RESET_MEM"
export CFLAGS

cd "$ROOT"
make clean > /dev/null
make all
make -C tests native

cd "$ROOT/tests"

VG="valgrind --quiet --leak-check=yes --error-exitcode=1"

./datagen -s1 -g16KB > tmp.vg

echo "== block compression =="
$VG ../programs/lizard -19 -BD -f tmp.vg /dev/null
$VG ../programs/lizard -30 -f tmp.vg tmp.vg.liz
$VG ../programs/lizard -49 -f tmp.vg tmp.vg.liz
$VG ../programs/lizard -t tmp.vg.liz
$VG ../programs/lizard -d -f tmp.vg.liz tmp.vg.out
cmp tmp.vg tmp.vg.out

echo "== multiple files =="
./datagen -s2 -g16KB > tmp.vg2
./datagen -s3 -g16KB > tmp.vg3
$VG ../programs/lizard -f -m tmp.vg tmp.vg2 tmp.vg3
$VG ../programs/lizard -d -f -m tmp.vg.liz tmp.vg2.liz tmp.vg3.liz

echo "== bench mode =="
$VG ../programs/lizard -bi1 tmp.vg

echo "== fullbench =="
$VG ./fullbench -i1 tmp.vg

echo "== frametest =="
$VG ./frametest -i64

echo "== fuzzer =="
$VG ./fuzzer --no-prompt -i64 -t1

rm -f tmp.vg tmp.vg2 tmp.vg3 tmp.vg.liz tmp.vg2.liz tmp.vg3.liz tmp.vg.out
echo "valgrind suite: OK"
