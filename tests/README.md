Programs and scripts for automated testing of Lizard
=======================================================

This directory contains the following programs and scripts:
- `datagen` : Synthetic and parametrable data generator, for tests
- `frametest` : Test tool that checks lizard_frame integrity on target platform
- `fullbench`  : Precisely measure speed for each lizard inner functions
- `fuzzer`  : Test tool, to check lizard integrity on target platform

Bounded suites (what CI runs on every push)
-------------------------------------------------------

- `test-fast.sh` : the parts of the suite that finish in a few minutes:
  `fullbench`, `frametest`, a 20 second `fuzzer` run and the command line cases
  (`test-lizard-basic`, `-multiple`, `-sparse`, `-frame-concatenation`,
  `-testmode`).  The multi-gigabyte cases (`test-lizard-hugefile`, the 3 GB part
  of `test-lizard-contentSize`) stay in `make test`.
- `test-valgrind.sh` : the same paths under valgrind, on small inputs.  The
  tree is built with `-DLIZARD_RESET_MEM`, as the `msan` and `asan` targets do:
  the match finder leaves its tables uninitialised on purpose and relies on
  bounds checks, and memcheck would report those reads and bury anything real.
- `test-poisoned-heap.sh` : compresses the same input at every level with a
  zeroed heap and with `MALLOC_PERTURB_` set, and requires identical output.  A
  compressor that reads uninitialised memory fails here.

Fuzzing
-------------------------------------------------------

- `fuzz_decode.c` : libFuzzer harness for the decoders.  It feeds arbitrary
  bytes to `LizardF_decompress` (in one call, one byte at a time, and in
  chunks that follow the decoder's own hint) and to `Lizard_decompress_safe`,
  and requires a clean failure: an error, not a crash, a hang or a read past
  the input.  Built with ASan and UBSan.
- `test-fuzz.sh [seconds]` : builds the harness, seeds a corpus with valid
  streams of every compression method and runs it for 60 seconds by default.
  CI runs it for two minutes on every push.

Cross-build compatibility
-------------------------------------------------------

- `build-matrix.sh` : builds every target whose toolchain is installed
  (`linux-x64`, `linux-i386`, `linux-arm64`, `win-x64`, `win-x86`) into one
  directory.  Missing toolchains are skipped, not fatal.
- `test_interop.sh <binary> ...` : the compatibility guarantee of the project.
  Every binary compresses the same deterministic corpus at every level, and

  1. every stream must decode, byte for byte, with every binary, and
  2. builds that share a pointer width must produce identical bytes.

  The 32-bit and 64-bit builds are allowed to differ from each other: the match
  finder works on offsets, so the word size changes which matches are found.
  The stream format itself does not change, which is what rule 1 checks.

  The runner is chosen per binary: `*.exe` runs under wine, an aarch64 ELF runs
  under `qemu-aarch64`, everything else runs natively.  `make test-interop`
  builds the matrix and runs it.

Rules for new tests
-------------------------------------------------------

- No test may need more than a few minutes of CPU or more than a few hundred
  megabytes of temporary space; the heavy cases stay behind `make test`.
- A test that reads a compressed stream must check the decompressed bytes, not
  only the exit code.
- Anything that a different compiler could reasonably get wrong (word size,
  endianness, alignment, uninitialised memory) belongs in one of the suites
  above rather than in a one-off script.


#### License

All files in this directory are licensed under GPL-v2.
See [COPYING](COPYING) for details.
The text of the license is also included at the top of each source file.
