/*
 * fuzz_decode.c - libFuzzer harness for the Lizard decoders
 *
 * The fuzzer in this directory checks the round trip on data it generates.
 * This one starts from arbitrary bytes: it takes a stream that may be
 * corrupted, truncated or simply not a stream at all, and requires the
 * decoder to fail cleanly -- an error, not a crash, a hang or a read past the
 * buffers.  Built with -fsanitize=fuzzer,address,undefined, so a bad read or
 * an undefined operation is a finding.
 *
 * Build:  make -C tests fuzz_decode
 * Run:    tests/test-fuzz.sh          (builds, seeds a corpus, runs for a while)
 *         tests/fuzz_decode -max_total_time=60 corpus/
 *
 * SPDX-License-Identifier: GPL-2.0
 */

#include <stddef.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

#include "lizard_compress.h"
#include "lizard_decompress.h"
#include "lizard_frame.h"

#define OUT_CAP (4u << 20)

static unsigned char g_out[OUT_CAP];

/* The frame decoder is a state machine: how the input is cut into calls
 * matters, so the first byte of the input picks the feeding strategy. */
static void try_frame(const uint8_t* data, size_t size)
{
    LizardF_decompressionContext_t ctx;

    if (LizardF_isError(LizardF_createDecompressionContext(&ctx, LIZARDF_VERSION))) return;

    switch (data[0] % 3) {
    case 0: {   /* everything in one call */
        size_t inSize = size;
        size_t outSize = OUT_CAP;
        (void)LizardF_decompress(ctx, g_out, &outSize, data, &inSize, NULL);
        break;
    }
    case 1: {   /* one byte at a time, the worst case for the state machine */
        size_t pos = 0, outPos = 0;
        while (pos < size && outPos < OUT_CAP) {
            size_t inSize = 1;
            size_t outSize = OUT_CAP - outPos;
            size_t hint = LizardF_decompress(ctx, g_out + outPos, &outSize, data + pos, &inSize, NULL);
            pos += inSize;
            outPos += outSize;
            if (LizardF_isError(hint)) break;
            if (inSize == 0 && outSize == 0) break;   /* no progress, stop */
        }
        break;
    }
    default: {  /* chunks whose size follows the decoder's own hint */
        size_t pos = 0, outPos = 0, step = 2;
        while (pos < size && outPos < OUT_CAP) {
            size_t inSize = step;
            size_t outSize = OUT_CAP - outPos;
            size_t hint;
            if (inSize > size - pos) inSize = size - pos;
            hint = LizardF_decompress(ctx, g_out + outPos, &outSize, data + pos, &inSize, NULL);
            pos += inSize;
            outPos += outSize;
            if (LizardF_isError(hint)) break;
            step = (hint % 97) + 1;
        }
        break;
    }
    }

    LizardF_freeDecompressionContext(ctx);
}

/* The block decoder takes the compression level from the first byte of the
 * payload, so arbitrary input still reaches the match copier. */
static void try_block(const uint8_t* data, size_t size)
{
    if (size < 2 || size > (16u << 20)) return;
    (void)Lizard_decompress_safe((const char*)data, (char*)g_out, (int)size, (int)OUT_CAP);
}

int LLVMFuzzerTestOneInput(const uint8_t* data, size_t size)
{
    if (size == 0) return 0;
    try_frame(data, size);
    try_block(data, size);
    return 0;
}
