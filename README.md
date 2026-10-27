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
[wBench2025]: https://github.com/YadeWira/lizard-ex/wiki/Author-Benchmarks-2025
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
Back in 2017, Lizard 1.0 filled a niche between [LZ4] and [zstd] in terms of compression ratio, as well as compression and decompression speed. However, based on benchmarks conducted in 2025 (shared in the [wiki][wBench2025]), both LZ4 and zstd have made substantial advancements, particularly in compression and decompression speed, leaving Lizard outdated and effectively obsolete.


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

### The original author's run

The 2025 benchmark in which Lizard was declared obsolete — an EPYC 9554, the
full lz4/lz4hc/zstd/zlib/brotli comparison — is in the wiki, as written:
[Author benchmarks 2025][wBench2025].  It is not comparable with the table
above (different machine, different tools) and it is not updated by this line.

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
