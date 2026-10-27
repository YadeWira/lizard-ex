lizard-ex - the maintained line of Lizard
--------------------------------------------------------

**lizard-ex** is the maintenance line of [Lizard], the compressor with very
fast decompression.  The code base is Lizard 2.1, with its API, its block and
frame formats and its compression levels **unchanged**: a stream written here
decodes with Lizard 2.1, and 2.2.2 and later produce the same bytes as the
release before them.

| Component | Status |
|-----------|--------|
| CI | [![CI][ciBadge]][ciLink] |
| Latest release | [![Release][relBadge]][relLink] |

Quick start
--------------------------------------------------------

```sh
make                       # lib/liblizard.{a,so} and programs/lizard
make test-fast             # bounded regression suite, a few minutes
make test-binary           # 234 command line checks on the built program
make test-fuzz             # decoder fuzzing (libFuzzer + ASan/UBSan), one minute
make test-interop          # cross-build stream compatibility (needs cross toolchains)
make windows               # Windows x64 lizard.exe with mingw-w64
programs/lizard -29 file   # compress to file.liz
programs/lizard -d file.liz
```

```c
#include "lizard_compress.h"
#include "lizard_decompress.h"

int bound = Lizard_compressBound(srcSize);
int csize = Lizard_compress(src, dst, srcSize, bound, 29);
int dsize = Lizard_decompress_safe(dst, out, csize, outCapacity);   /* < 0 if damaged */
```

What this line adds
--------------------------------------------------------

The format and the tuning are not touched; what is added is the part a library
needs to stay usable:

- **A matrix that is actually run on every push.**  Linux x86_64 (gcc, clang,
  `-Werror`, `-Wconversion`, ASan, UBSan), Linux i386, Linux arm64 on a native
  runner, Windows x86 and x86_64 built with mingw-w64 and executed on a Windows
  runner, macOS arm64.
- **A portability guarantee that is checked, not assumed.**  `make test-interop`
  requires every stream to decode with every build, and builds that share a
  pointer width to produce identical bytes.
- **Fuzzing.**  `make test-fuzz` feeds arbitrary and corrupted bytes to the
  decoders under ASan and UBSan, whole, byte by byte and in chunks that follow
  the decoder's own hint.  It found a read past the input in the LIZv1 literal
  copy (fixed in 2.2.1) in its first minute.
- **Fixes for what the matrix and the fuzzers find**: undefined behaviour in
  the frame and block decoders, a stored block that MSVC x64 decoded as
  compressed, `-t` reporting success on a file that does not exist.  The list
  is in [`NEWS`](NEWS).
- **Release binaries** for six targets, reproducible from the tag, with
  `SHA256SUMS`, each one checked with `tests/test_binary.sh` before it is
  attached.

Windows, without Visual Studio
--------------------------------------------------------

`make windows` cross-compiles a **statically linked** `lizard.exe` with
mingw-w64 from any POSIX host; `make windows WINCC=i686-w64-mingw32-gcc` does
the 32-bit one.  That is the toolchain the release binaries come from, and CI
runs them on a real Windows runner before they are attached.

**Visual Studio is not supported**: the projects were removed in 2.3.0.  If you
built inside Visual Studio, either use `make windows` or stay on 2.2.2.

Compatibility
--------------------------------------------------------

The block format, the frame format, the API and the levels are Lizard 2.1's.  A
stream written by this line decodes with Lizard 2.1, and the other way round;
since 2.2.2 the compressed output is byte-identical release to release.

The one thing this line deliberately does **not** do is emit offsets below 8.
They are legal in the format, and 2.2.1 and later decoders handle them, but
Lizard 2.1 copies them wrong, so enabling them would break the guarantee above.
They cost about 2 % of ratio at the fast levels; see [compatibility][wCompat].

**Documentation is in the [wiki][wiki]**: [getting started][wGS], [compression
levels][wCL], [library API][wAPI], [compatibility][wCompat], [building][wBuild]
and [testing][wTest].

Lizard - efficient compression with very fast decompression
--------------------------------------------------------

The rest of this file describes the algorithm as the original author wrote it.

Lizard (formerly LZ5) is a lossless compression algorithm which contains 4 compression methods:
- fastLZ4 : compression levels -10...-19 are designed to give fast decompression speed
- LIZv1 : compression levels -20...-29 are designed to give better compression ratio keeping 75% of decompression speed
- fastLZ4 + Huffman : compression levels -30...-39 add Huffman coding to fastLZ4
- LIZv1 + Huffman : compression levels -40...-49 give the best ratio (comparable to [zlib] and low levels of [zstd]/[brotli])

Lizard library is based on frequently used [LZ4] library by Yann Collet but the Lizard compression format is not compatible with LZ4.
Lizard library is provided as open-source software using BSD 2-Clause license.
The high compression/decompression speed is achieved without any SSE and AVX extensions.


[Lizard]: https://github.com/inikep/lizard
[wiki]: https://github.com/YadeWira/lizard-ex/wiki
[wGS]: https://github.com/YadeWira/lizard-ex/wiki/Getting-Started
[wCL]: https://github.com/YadeWira/lizard-ex/wiki/Compression-Levels
[wAPI]: https://github.com/YadeWira/lizard-ex/wiki/Library-API
[wCompat]: https://github.com/YadeWira/lizard-ex/wiki/Compatibility
[wBuild]: https://github.com/YadeWira/lizard-ex/wiki/Building
[wTest]: https://github.com/YadeWira/lizard-ex/wiki/Testing
[ciBadge]: https://github.com/YadeWira/lizard-ex/actions/workflows/ci.yml/badge.svg "Continuous Integration"
[ciLink]: https://github.com/YadeWira/lizard-ex/actions/workflows/ci.yml
[relBadge]: https://img.shields.io/github/v/release/YadeWira/lizard-ex "Latest release"
[relLink]: https://github.com/YadeWira/lizard-ex/releases/latest

[LZ4]: https://github.com/lz4/lz4
[zlib]: https://github.com/madler/zlib
[zstd]: https://github.com/facebook/zstd
[brotli]: https://github.com/google/brotli


2025 Update
--------------------------------------------------------
Back in 2017, Lizard 1.0 filled a niche between [LZ4] and [zstd] in terms of compression ratio, as well as compression and decompression speed. However, based on benchmarks conducted in 2025 (shared below), both LZ4 and zstd have made substantial advancements, particularly in compression and decompression speed, leaving Lizard outdated and effectively obsolete.


Benchmarks
-------------------------

Measured for this line on a **single core of an Intel Xeon E5-2697A v4 at
2.60 GHz**, Ubuntu 24.04, gcc 14.2, on `silesia.tar` (211,957,760 bytes).  Each
tool ran its own in-memory benchmark (`-b<level> -i2`), best of three runs.
`lizard-ex` is 2.3.0, LZ4 is 1.10.0 and zstd is 1.5.7.

These numbers are not comparable with the table further down: different
machine, different tools.  They are here so the trade-offs of this library can
be read against the two compressors it is measured against, on the same box.

| Compressor | Level | Size | Ratio | Compression | Decompression |
|---|---|---|---|---|---|
| **lizard-ex 2.3.0** | `-10` | 103.4 MB | 2.050 | 445 MB/s | 2560 MB/s |
| **lizard-ex 2.3.0** | `-12` | 86.2 MB | 2.458 | 117 MB/s | 2458 MB/s |
| **lizard-ex 2.3.0** | `-16` | 79.4 MB | 2.671 | 42.8 MB/s | 2458 MB/s |
| **lizard-ex 2.3.0** | `-19` | 77.4 MB | 2.738 | 4.1 MB/s | 2413 MB/s |
| **lizard-ex 2.3.0** | `-20` | 96.9 MB | 2.187 | 326 MB/s | 1758 MB/s |
| **lizard-ex 2.3.0** | `-26` | 72.5 MB | 2.925 | 6.4 MB/s | 1529 MB/s |
| **lizard-ex 2.3.0** | `-30` | 85.8 MB | 2.471 | 329 MB/s | 1137 MB/s |
| **lizard-ex 2.3.0** | `-40` | 80.8 MB | 2.622 | 240 MB/s | 1049 MB/s |
| **lizard-ex 2.3.0** | `-49` | 60.7 MB | 3.490 | 1.9 MB/s | 1084 MB/s |
| lz4 1.10.0 | `-1` | 100.9 MB | 2.101 | 530 MB/s | 3314 MB/s |
| lz4 1.10.0 | `-3` | 81.3 MB | 2.606 | 77.0 MB/s | 3172 MB/s |
| lz4 1.10.0 | `-9` | 77.9 MB | 2.721 | 28.9 MB/s | 3182 MB/s |
| lz4 1.10.0 | `-12` | 77.3 MB | 2.743 | 9.7 MB/s | 2931 MB/s |
| zstd 1.5.7 | `-1` | 73.3 MB | 2.892 | 1057 MB/s | 947 MB/s |
| zstd 1.5.7 | `-3` | 66.3 MB | 3.198 | 530 MB/s | 702 MB/s |
| zstd 1.5.7 | `-9` | 59.2 MB | 3.581 | 176 MB/s | 528 MB/s |
| zstd 1.5.7 | `-19` | 52.9 MB | 4.010 | 7.9 MB/s | 529 MB/s |

Read it as what it is: LZ4 is faster on both sides at a slightly better ratio,
zstd reaches a much better ratio while decoding at half to a quarter of the
speed, and Lizard sits in between — its decoder is the cheap one, which is what
it was built for.  2.2.2 made the fast levels about 8 % faster to compress than
2.2.1 with identical output; see [`NEWS`](NEWS).

### The original author's run (2025)

These are the numbers in which Lizard was declared obsolete.  They are kept as
they were written, and are the reference for the claims in the next section.

The following results were obtained using [lzbench 2.0](https://github.com/inikep/lzbench), built with `gcc 14.2.0` and executed with the options ` -t16,16 -o1c4 -elz4/lz4hc/lizard/zstd_fast/zstd/zlib/brotli`.
The tests were run on a single core of an AMD EPYC 9554 processor at 3.10 GHz, with the CPU governor set to `performance` and turbo
boost disabled for stability. The operating system was `Ubuntu 24.04.1`, and the benchmark made use of
[`silesia.tar`](https://github.com/DataCompression/corpus-collection/tree/main/Silesia-Corpus), which contains tarred files from the
[Silesia compression corpus](http://sun.aei.polsl.pl/~sdeor/index.php?page=silesia).

| Compressor name         | Compression| Decompress.| Compr. size | Ratio |
| ---------------         | -----------| -----------| ----------- | ----- |
| memcpy                  | 16253 MB/s | 16151 MB/s |   211947520 |100.00 |
| lz4 1.10.0              |   579 MB/s |  3728 MB/s |   100880800 | 47.60 |
| lz4hc 1.10.0 -1         |   265 MB/s |  3225 MB/s |    89135429 | 42.06 |
| lz4hc 1.10.0 -2         |   265 MB/s |  3227 MB/s |    89135429 | 42.06 |
| lz4hc 1.10.0 -3         |  92.7 MB/s |  3373 MB/s |    81342421 | 38.38 |
| lz4hc 1.10.0 -4         |  76.6 MB/s |  3429 MB/s |    79807909 | 37.65 |
| lz4hc 1.10.0 -5         |  62.6 MB/s |  3474 MB/s |    78895329 | 37.22 |
| lz4hc 1.10.0 -6         |  51.4 MB/s |  3494 MB/s |    78385708 | 36.98 |
| lz4hc 1.10.0 -7         |  42.7 MB/s |  3511 MB/s |    78102452 | 36.85 |
| lz4hc 1.10.0 -8         |  36.1 MB/s |  3525 MB/s |    77957479 | 36.78 |
| lz4hc 1.10.0 -9         |  31.0 MB/s |  3531 MB/s |    77884448 | 36.75 |
| lz4hc 1.10.0 -10        |  21.4 MB/s |  3604 MB/s |    77596766 | 36.61 |
| lz4hc 1.10.0 -11        |  12.5 MB/s |  3630 MB/s |    77315480 | 36.48 |
| lz4hc 1.10.0 -12        |  10.5 MB/s |  3622 MB/s |    77262620 | 36.45 |
| lizard 2.1 -10          |   484 MB/s |  2161 MB/s |   103402971 | 48.79 |
| lizard 2.1 -11          |   316 MB/s |  1935 MB/s |    93861621 | 44.29 |
| lizard 2.1 -12          |   166 MB/s |  2005 MB/s |    86232422 | 40.69 |
| lizard 2.1 -13          |   102 MB/s |  2040 MB/s |    83773119 | 39.53 |
| lizard 2.1 -14          |  90.3 MB/s |  2082 MB/s |    82205976 | 38.79 |
| lizard 2.1 -15          |  77.8 MB/s |  2106 MB/s |    81187330 | 38.31 |
| lizard 2.1 -16          |  56.0 MB/s |  1951 MB/s |    79372512 | 37.45 |
| lizard 2.1 -17          |  26.5 MB/s |  1986 MB/s |    78041714 | 36.82 |
| lizard 2.1 -18          |  6.67 MB/s |  1978 MB/s |    77586984 | 36.61 |
| lizard 2.1 -19          |  4.81 MB/s |  1989 MB/s |    77416400 | 36.53 |
| lizard 2.1 -20          |   388 MB/s |  1674 MB/s |    96924204 | 45.73 |
| lizard 2.1 -21          |   229 MB/s |  1748 MB/s |    89239174 | 42.10 |
| lizard 2.1 -22          |   162 MB/s |  1709 MB/s |    84866725 | 40.04 |
| lizard 2.1 -23          |  64.5 MB/s |  1769 MB/s |    81052209 | 38.24 |
| lizard 2.1 -24          |  36.8 MB/s |  1792 MB/s |    78170875 | 36.88 |
| lizard 2.1 -25          |  22.3 MB/s |  1748 MB/s |    75131286 | 35.45 |
| lizard 2.1 -26          |  6.33 MB/s |  1767 MB/s |    72459161 | 34.19 |
| lizard 2.1 -27          |  4.46 MB/s |  1813 MB/s |    70447615 | 33.24 |
| lizard 2.1 -28          |  2.43 MB/s |  1821 MB/s |    69762972 | 32.92 |
| lizard 2.1 -29          |  2.13 MB/s |  1818 MB/s |    68694227 | 32.41 |
| lizard 2.1 -30          |   363 MB/s |  1185 MB/s |    85727429 | 40.45 |
| lizard 2.1 -31          |   263 MB/s |  1325 MB/s |    81688522 | 38.54 |
| lizard 2.1 -32          |   164 MB/s |  1274 MB/s |    78652654 | 37.11 |
| lizard 2.1 -33          |   151 MB/s |  1410 MB/s |    76929454 | 36.30 |
| lizard 2.1 -34          |  96.6 MB/s |  1477 MB/s |    75427930 | 35.59 |
| lizard 2.1 -35          |  85.7 MB/s |  1542 MB/s |    74563583 | 35.18 |
| lizard 2.1 -36          |  74.7 MB/s |  1573 MB/s |    73850400 | 34.84 |
| lizard 2.1 -37          |  54.5 MB/s |  1521 MB/s |    71854743 | 33.90 |
| lizard 2.1 -38          |  26.2 MB/s |  1565 MB/s |    70968686 | 33.48 |
| lizard 2.1 -39          |  4.66 MB/s |  1509 MB/s |    69807522 | 32.94 |
| lizard 2.1 -40          |   297 MB/s |  1141 MB/s |    80843049 | 38.14 |
| lizard 2.1 -41          |   192 MB/s |  1202 MB/s |    76100661 | 35.91 |
| lizard 2.1 -42          |   142 MB/s |  1231 MB/s |    73350988 | 34.61 |
| lizard 2.1 -43          |  59.7 MB/s |  1325 MB/s |    70927858 | 33.46 |
| lizard 2.1 -44          |  34.4 MB/s |  1353 MB/s |    68763512 | 32.44 |
| lizard 2.1 -45          |  21.7 MB/s |  1345 MB/s |    66676653 | 31.46 |
| lizard 2.1 -46          |  11.4 MB/s |  1201 MB/s |    65413061 | 30.86 |
| lizard 2.1 -47          |  6.07 MB/s |  1271 MB/s |    63704146 | 30.06 |
| lizard 2.1 -48          |  4.31 MB/s |  1297 MB/s |    62097965 | 29.30 |
| lizard 2.1 -49          |  2.08 MB/s |  1316 MB/s |    60679215 | 28.63 |
| zstd_fast 1.5.6 --5     |   573 MB/s |  1948 MB/s |   103093752 | 48.64 |
| zstd_fast 1.5.6 --4     |   542 MB/s |  1905 MB/s |    98825267 | 46.63 |
| zstd_fast 1.5.6 --3     |   518 MB/s |  1818 MB/s |    94674672 | 44.67 |
| zstd_fast 1.5.6 --2     |   489 MB/s |  1773 MB/s |    90474358 | 42.69 |
| zstd_fast 1.5.6 --1     |   459 MB/s |  1716 MB/s |    86984009 | 41.04 |
| zstd 1.5.6 -1           |   421 MB/s |  1342 MB/s |    73421914 | 34.64 |
| zstd 1.5.6 -2           |   344 MB/s |  1241 MB/s |    69503444 | 32.79 |
| zstd 1.5.6 -3           |   250 MB/s |  1210 MB/s |    66523842 | 31.39 |
| zstd 1.5.6 -4           |   214 MB/s |  1192 MB/s |    65323637 | 30.82 |
| zstd 1.5.6 -5           |   125 MB/s |  1194 MB/s |    63040310 | 29.74 |
| zstd 1.5.6 -6           |  91.7 MB/s |  1272 MB/s |    61540426 | 29.04 |
| zstd 1.5.6 -7           |  80.7 MB/s |  1283 MB/s |    60546558 | 28.57 |
| zstd 1.5.6 -8           |  64.1 MB/s |  1316 MB/s |    60015064 | 28.32 |
| zstd 1.5.6 -9           |  61.9 MB/s |  1306 MB/s |    59375344 | 28.01 |
| zstd 1.5.6 -10          |  48.0 MB/s |  1323 MB/s |    58675464 | 27.68 |
| zstd 1.5.6 -11          |  34.5 MB/s |  1339 MB/s |    58262299 | 27.49 |
| zstd 1.5.6 -12          |  31.8 MB/s |  1339 MB/s |    58206982 | 27.46 |
| zstd 1.5.6 -13          |  14.2 MB/s |  1343 MB/s |    57986550 | 27.36 |
| zstd 1.5.6 -14          |  11.3 MB/s |  1360 MB/s |    57575723 | 27.17 |
| zstd 1.5.6 -15          |  8.39 MB/s |  1368 MB/s |    57168834 | 26.97 |
| zstd 1.5.6 -16          |  6.13 MB/s |  1255 MB/s |    55304789 | 26.09 |
| zstd 1.5.6 -17          |  4.76 MB/s |  1226 MB/s |    54243339 | 25.59 |
| zstd 1.5.6 -18          |  3.76 MB/s |  1164 MB/s |    53329873 | 25.16 |
| zstd 1.5.6 -19          |  2.98 MB/s |  1147 MB/s |    52875116 | 24.95 |
| zstd 1.5.6 -20          |  2.73 MB/s |  1079 MB/s |    52456743 | 24.75 |
| zstd 1.5.6 -21          |  2.40 MB/s |  1075 MB/s |    52344203 | 24.70 |
| zstd 1.5.6 -22          |  2.09 MB/s |  1071 MB/s |    52333880 | 24.69 |
| zlib 1.3.1 -1           |  93.2 MB/s |   323 MB/s |    77259029 | 36.45 |
| zlib 1.3.1 -2           |  83.4 MB/s |   333 MB/s |    75002277 | 35.39 |
| zlib 1.3.1 -3           |  60.3 MB/s |   344 MB/s |    72967040 | 34.43 |
| zlib 1.3.1 -4           |  58.4 MB/s |   334 MB/s |    71002817 | 33.50 |
| zlib 1.3.1 -5           |  39.2 MB/s |   337 MB/s |    69161685 | 32.63 |
| zlib 1.3.1 -6           |  25.3 MB/s |   344 MB/s |    68228431 | 32.19 |
| zlib 1.3.1 -7           |  20.3 MB/s |   345 MB/s |    67939647 | 32.05 |
| zlib 1.3.1 -8           |  13.1 MB/s |   347 MB/s |    67693427 | 31.94 |
| zlib 1.3.1 -9           |  10.3 MB/s |   348 MB/s |    67644548 | 31.92 |
| brotli 1.1.0 -0         |   341 MB/s |   352 MB/s |    78433298 | 37.01 |
| brotli 1.1.0 -1         |   234 MB/s |   379 MB/s |    73499222 | 34.68 |
| brotli 1.1.0 -2         |   139 MB/s |   415 MB/s |    68069489 | 32.12 |
| brotli 1.1.0 -3         |   116 MB/s |   429 MB/s |    67392492 | 31.80 |
| brotli 1.1.0 -4         |  80.3 MB/s |   452 MB/s |    64122989 | 30.25 |
| brotli 1.1.0 -5         |  36.9 MB/s |   450 MB/s |    59555446 | 28.10 |
| brotli 1.1.0 -6         |  26.9 MB/s |   457 MB/s |    58470465 | 27.59 |
| brotli 1.1.0 -7         |  17.5 MB/s |   472 MB/s |    57688191 | 27.22 |
| brotli 1.1.0 -8         |  12.4 MB/s |   476 MB/s |    57148304 | 26.96 |
| brotli 1.1.0 -9         |  9.19 MB/s |   480 MB/s |    56703946 | 26.75 |
| brotli 1.1.0 -10        |  1.25 MB/s |   345 MB/s |    51720800 | 24.40 |
| brotli 1.1.0 -11        |  0.58 MB/s |   387 MB/s |    50407795 | 23.78 |


Building and testing
-------------------------

The compilers, the flags and what each suite covers are in the wiki:
[building][wBuild] and [testing][wTest].  In short: gcc and clang on Linux and
macOS, mingw-w64 for Windows, and no Visual Studio anywhere.


Documentation
-------------------------

The raw Lizard block compression format is detailed within [lizard_Block_format].

To compress an arbitrarily long file or data stream, multiple blocks are required.
Organizing these blocks and providing a common header format to handle their content
is the purpose of the Frame format, defined into [lizard_Frame_format].
Interoperable versions of Lizard must respect this frame format.

[lizard_Block_format]: doc/lizard_Block_format.md
[lizard_Frame_format]: doc/lizard_Frame_format.md
