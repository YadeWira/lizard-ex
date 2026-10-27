lizard-ex - the maintained line of Lizard
--------------------------------------------------------

**lizard-ex** is the maintenance line of [Lizard], the compressor with very fast
decompression.  The code base is Lizard 2.1, with its API and its block and
frame formats **unchanged**: anything that reads or writes Lizard 2.1 streams
keeps working, and a stream written here decodes with Lizard 2.1 and the other
way round.

What this line adds is the part a library needs to stay usable:

- **A build and test matrix that is actually run.**  Linux x86, x86_64 and
  arm64, Windows x86 and x86_64, macOS arm64.  Every push builds all of them,
  runs the bounded test suite (fuzzer, frame tester, fullbench, the command
  line cases) and runs ASan, UBSan and valgrind.
- **A portability guarantee that is checked, not assumed.**  Every stream
  produced by any of those builds must decode with all the others, and builds
  that share a pointer width must produce identical bytes.  `make test-interop`
  does exactly that with the binaries of all five targets.
- **Compression that does not depend on the state of the heap.**
  `make test-poisoned-heap` proves the output is a function of the input only.
- **Fixes for the defects the matrix finds.**  See [`NEWS`](NEWS).

Lizard the algorithm is not changed here: the compressed format, the levels and
the tuning stay exactly as they were.  If you are looking for a new compressor,
read the note from the original author below; zstd covers what Lizard used to
cover in 2017.  If you have data compressed with Lizard, or a build of an old
Lizard that no longer compiles on your toolchain, this is the line to use.

| Component | Status |
|-----------|--------|
| CI (Linux x86/x64/arm64, Windows x86/x64, macOS arm64) | [![CI][ciBadge]][ciLink] |

**Documentation is in the [wiki][wiki]**: [getting started][wGS], [compression
levels][wCL], [library API][wAPI], [compatibility][wCompat], [building][wBuild]
and [testing][wTest].

Quick start
--------------------------------------------------------

```sh
make                       # lib/liblizard.{a,so} and programs/lizard
make test-fast             # bounded regression suite, a few minutes
make test-interop          # cross-build stream compatibility (needs cross toolchains)
make windows               # Windows x64 lizard.exe with mingw-w64 (see below)
programs/lizard -29 file   # compress to file.liz
programs/lizard -d file.liz
```

Windows does not need Visual Studio: `make windows` cross-compiles a statically
linked `lizard.exe` with mingw-w64 from any POSIX host, and
`make windows WINCC=i686-w64-mingw32-gcc` does the 32-bit one.  Those are the
toolchains the Windows release binaries come from, and CI runs the resulting
binaries on a real Windows runner before they are attached to a release.
Visual Studio is not supported: the projects were removed in 2.3.0.

```c
#include "lizard_compress.h"
#include "lizard_decompress.h"

int bound = Lizard_compressBound(srcSize);
int csize = Lizard_compress(src, dst, srcSize, bound, 29);
int dsize = Lizard_decompress_safe(dst, out, csize, outCapacity);
```

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

[LZ4]: https://github.com/lz4/lz4
[zlib]: https://github.com/madler/zlib
[zstd]: https://github.com/facebook/zstd
[brotli]: https://github.com/google/brotli


2025 Update
--------------------------------------------------------
Back in 2017, Lizard 1.0 filled a niche between [LZ4] and [zstd] in terms of compression ratio, as well as compression and decompression speed. However, based on benchmarks conducted in 2025 (shared below), both LZ4 and zstd have made substantial advancements, particularly in compression and decompression speed, leaving Lizard outdated and effectively obsolete.


Benchmarks
-------------------------

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


Automatic CI/CD testing
-------------------------

lizard undergoes automated testing using Azure Pipelines with the following compilers:
- Ubuntu: gcc (versions 7.5 to 14.2) and clang (versions 6.0 to 19), gcc 14.2 (32-bit)
- MacOS: Apple LLVM version 15.0.0
- Windows: mingw32-gcc 14.2.0 (32-bit) and mingw64-gcc 14.2.0 (64-bit)
- Cross-compilation: gcc for ARM (32-bit and 64-bit) and PowerPC (32-bit and 64-bit)


Documentation
-------------------------

The raw Lizard block compression format is detailed within [lizard_Block_format].

To compress an arbitrarily long file or data stream, multiple blocks are required.
Organizing these blocks and providing a common header format to handle their content
is the purpose of the Frame format, defined into [lizard_Frame_format].
Interoperable versions of Lizard must respect this frame format.

[lizard_Block_format]: doc/lizard_Block_format.md
[lizard_Frame_format]: doc/lizard_Frame_format.md
