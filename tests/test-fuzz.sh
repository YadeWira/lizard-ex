#!/bin/sh
# test-fuzz.sh - run the libFuzzer harness on the decoders
#
# Builds tests/fuzz_decode with ASan and UBSan, seeds the corpus with valid
# streams from every compression method (so the fuzzer starts from something
# that decodes instead of looking for the header from scratch) and runs it for
# FUZZ_TIME seconds, 60 by default.  A corpus that already exists is kept and
# extended.
#
# Usage:  tests/test-fuzz.sh [seconds]
#
# A finding is a crash, a sanitizer report or a timeout; libFuzzer exits
# non-zero and leaves the reproducer in tests/crash-*.

set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT/tests"

SECONDS_TO_RUN=${1:-${FUZZ_TIME:-60}}
CORPUS=corpus

echo "== build =="
make fuzz_decode CC=${CC:-clang}
make datagen CC=${CC:-clang} > /dev/null
make -C "$ROOT/programs" lizard CC=${CC:-clang} > /dev/null

echo "== seed corpus =="
# An existing corpus is kept: nightly runs restore it from the cache so the
# fuzzer spends its time on new paths, and this only adds the seeds.
mkdir -p "$CORPUS"
make mkblock CC=${CC:-clang} > /dev/null
i=0
for lvl in 10 13 16 19 20 23 26 29 30 33 36 39 40 43 46 49; do
    for size in 0 1 2 7 64 1000 70000; do
        i=$((i + 1))
        ./datagen -s"$i" -g"$size" -P50 > seed.raw 2>/dev/null || : > seed.raw
        "$ROOT/programs/lizard" -"$lvl" -q -c seed.raw > "$CORPUS/seed-$lvl-$size" 2>/dev/null || true
    done
done
# A few corrupted variants make the first mutations more interesting.
for f in "$CORPUS"/seed-2*; do
    [ -f "$f" ] || continue
    cp "$f" "$f.bad"
    printf '\377\377\377\377' | dd of="$f.bad" bs=1 seek=0 conv=notrunc > /dev/null 2>&1
done
rm -f seed.raw "$CORPUS"/*.bad

# Block streams: the block decoder is a different code path from the frame
# (a level byte instead of a magic number), and the frame seeds never reach it.
# Mixed blocks matter: a stored block followed by a compressed one is where the
# output budget went wrong in 2.3.1.
i=0
for lvl in 10 17 20 26 30 36 40 46 49; do
    i=$((i + 1))
    ./datagen -s"$i" -g140000 -P0 > mixed.raw 2>/dev/null || : > mixed.raw
    ./datagen -s$((i + 100)) -g160000 -P99 >> mixed.raw 2>/dev/null || true
    ./mkblock "$lvl" < mixed.raw > "$CORPUS/block-$lvl-mixed" 2>/dev/null || true
    ./datagen -s"$i" -g70000 -P50 > seed.raw 2>/dev/null || : > seed.raw
    ./mkblock "$lvl" < seed.raw > "$CORPUS/block-$lvl" 2>/dev/null || true
done
rm -f mixed.raw seed.raw
echo "$(ls "$CORPUS" | wc -l | tr -d ' ') seeds"

echo
echo "== fuzzing for ${SECONDS_TO_RUN}s =="
./fuzz_decode -max_total_time="$SECONDS_TO_RUN" -rss_limit_mb=2048 -timeout=10 "$CORPUS"
