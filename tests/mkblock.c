/* mkblock.c - compress stdin to stdout with the block API.
 *
 * Usage:  mkblock <level> < input > block_stream
 *
 * The block API is what zpaq-std and the frame layer use internally, and it is
 * a different code path from the frame: a stream starts with the compression
 * level instead of a magic number.  tests/test-fuzz.sh uses this to seed the
 * fuzzer with block streams, which the harness otherwise barely reaches.
 *
 * SPDX-License-Identifier: GPL-2.0
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "lizard_compress.h"

#define CHUNK (1 << 20)

int main(int argc, char** argv)
{
    int level, bound, csize;
    unsigned char* in;
    unsigned char* out;
    size_t n = 0, cap = CHUNK;

    if (argc != 2) { fprintf(stderr, "usage: %s <level>\n", argv[0]); return 2; }
    level = atoi(argv[1]);
    if (level < 10 || level > 49) { fprintf(stderr, "level out of range\n"); return 2; }

    in = malloc(cap);
    if (!in) return 1;
    for (;;) {
        size_t r = fread(in + n, 1, cap - n, stdin);
        n += r;
        if (n < cap) break;
        cap *= 2;
        in = realloc(in, cap);
        if (!in) return 1;
    }
    if (n == 0) return 0;

    bound = Lizard_compressBound((int)n);
    out = malloc((size_t)bound);
    if (!out) return 1;
    csize = Lizard_compress((const char*)in, (char*)out, (int)n, bound, level);
    if (csize <= 0) { fprintf(stderr, "compression failed\n"); return 1; }
    if (fwrite(out, 1, (size_t)csize, stdout) != (size_t)csize) return 1;
    return 0;
}
