/* Deterministic regression: a stored block followed by a compressed block.
 *
 * The uncompressed path moves the output pointer without shrinking the
 * remaining output size, so the next block was decoded with an output end past
 * the caller's buffer.  Here the second block simply does not fit: a correct
 * decoder has to return an error, and a decoder that forgot to shrink the
 * budget returns success after writing past the end of the buffer (which
 * AddressSanitizer reports, and which the return value also gives away).
 *
 * The stream is built by hand:
 *   [level] [0x80 len(24) stored bytes] [compressed block from another buffer]
 *
 * Found by zpaq-std against 2.3.1; see NEWS.
 *
 * SPDX-License-Identifier: GPL-2.0
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "lizard_compress.h"
#include "lizard_decompress.h"

#define STORED_SIZE  140000
#define SECOND_SIZE  200000
#define OUT_SIZE     300000                       /* less than STORED + SECOND */
#define TOTAL        (STORED_SIZE + SECOND_SIZE)

static void fill_stored(unsigned char* p)
{
    unsigned s = 1;
    int i;
    for (i = 0; i < STORED_SIZE; i++) { s = s * 1103515245u + 12345u; p[i] = (unsigned char)(s >> 16); }
}

static void fill_text(unsigned char* p)
{
    static const char text[] = "the quick brown fox jumps over the lazy dog, again and again. ";
    int i;
    for (i = 0; i < SECOND_SIZE; i++) p[i] = (unsigned char)text[i % (sizeof(text) - 1)];
}

int main(void)
{
    unsigned char* stored = malloc(STORED_SIZE);
    unsigned char* text = malloc(SECOND_SIZE);
    unsigned char* out = malloc(OUT_SIZE);          /* exactly the caller's buffer */
    unsigned char* second = malloc((size_t)Lizard_compressBound(SECOND_SIZE));
    unsigned char* stream = malloc((size_t)Lizard_compressBound(TOTAL) + SECOND_SIZE + 16);
    int level, failed = 0, checked = 0;

    if (!stored || !text || !out || !second || !stream) { printf("allocation failure\n"); return 1; }
    fill_stored(stored);
    fill_text(text);

    for (level = 10; level <= 49; level++) {
        int secondSize, off = 0, dsize;

        /* A compressed block for the second half. */
        secondSize = Lizard_compress((const char*)text, (char*)second, SECOND_SIZE,
                                     Lizard_compressBound(SECOND_SIZE), level);
        if (secondSize <= 1) { printf("FAIL: level -%d cannot compress the second block\n", level); failed++; continue; }
        if ((unsigned char)second[0] != (unsigned char)level) {
            printf("FAIL: level -%d: the block does not start with the level\n", level); failed++; continue;
        }

        /* [level][stored block][compressed block] */
        stream[off++] = (unsigned char)level;
        stream[off++] = 0x80;                              /* LIZARD_FLAG_UNCOMPRESSED */
        stream[off++] = (unsigned char)(STORED_SIZE & 0xFF);
        stream[off++] = (unsigned char)((STORED_SIZE >> 8) & 0xFF);
        stream[off++] = (unsigned char)((STORED_SIZE >> 16) & 0xFF);
        memcpy(stream + off, stored, STORED_SIZE); off += STORED_SIZE;
        memcpy(stream + off, second + 1, (size_t)(secondSize - 1)); off += secondSize - 1;

        /* The output buffer is exactly OUT_SIZE: the second block cannot fit. */
        dsize = Lizard_decompress_safe((const char*)stream, (char*)out, off, OUT_SIZE);
        if (dsize >= 0) {
            printf("FAIL: level -%d decoded %d bytes into a %d byte buffer\n", level, dsize, OUT_SIZE);
            failed++;
            continue;
        }
        checked++;
    }

    free(stored); free(text); free(out); free(second); free(stream);

    if (failed) { printf("FAILED: %d level(s)\n", failed); return 1; }
    printf("OK: %d levels, stored block followed by a compressed one that does not fit\n", checked);
    return 0;
}
