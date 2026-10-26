#!/bin/sh
# test-poisoned-heap.sh - compression must not read uninitialised memory
#
# A hash table that is allocated but not cleared returns different bytes every
# time the heap is recycled, and the compressed output silently changes.  The
# output of a compressor must depend on the input only, so the same input is
# compressed at every level with a zeroed heap and with two different poisoned
# heaps, and the streams must be identical.
#
# Usage:  tests/test-poisoned-heap.sh     (or: make test-poisoned-heap)

set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT/tests"

hash() {
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum | cut -d' ' -f1
    else
        shasum -a 256 | cut -d' ' -f1
    fi
}

make native lizard

./datagen -s1 -g1M -P50 > tmp.ph

echo "== every level, with and without a poisoned heap =="
fail=0
for lvl in $(seq 10 49); do
    a=$(MALLOC_PERTURB_=0   ../programs/lizard -"$lvl" -q -c tmp.ph | hash)
    b=$(MALLOC_PERTURB_=170 ../programs/lizard -"$lvl" -q -c tmp.ph | hash)
    c=$(MALLOC_PERTURB_=85  ../programs/lizard -"$lvl" -q -c tmp.ph | hash)
    if [ "$a" != "$b" ] || [ "$a" != "$c" ]; then
        echo "level -$lvl is not deterministic under a poisoned heap"
        fail=$((fail + 1))
    fi
done

echo "== linked blocks =="
a=$(MALLOC_PERTURB_=0   ../programs/lizard -20 -BD -q -c tmp.ph | hash)
b=$(MALLOC_PERTURB_=170 ../programs/lizard -20 -BD -q -c tmp.ph | hash)
if [ "$a" != "$b" ]; then
    echo "level -20 -BD is not deterministic under a poisoned heap"
    fail=$((fail + 1))
fi

rm -f tmp.ph
if [ "$fail" -ne 0 ]; then
    echo "FAILED: $fail level(s) depend on uninitialised memory"
    exit 1
fi
echo "poisoned heap suite: OK"
