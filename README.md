# Software based FPU emulator

Femu is a software based fpu emulator for Amiga's without a real FPU. It was originally written by Jari Eskelinen. 
I've created a github repository to further develop and refine it -- notably, to remove dependency on the existing math libraries (breaking a weird circular dependency)
and also implement some performance improvements where possible (e.g., interpret following fpu opcodes without extra interrupt overhead, have single/double build options, relaxed IEEE enforcement, etc.).

Please be aware that software emulation is always much slower than real deal nor is compatibility perfect. YMMV, no guarantees, be happy if 
something actually works.

## Installation

Until this is fixed, if you are using OS 3.1 or 3.5, you need to copy following libraries from 
your OS 3.9 to your OS 3.1 or 3.5:

mathieeedoubbas.library
mathieeedoubtrans.library

Please backup originals first. Sorry, cannot distribute this libraries,
they are copyrighted work. Libraries from 3.1 or 3.5 won't work properly
due to bugs in them.

Extract to convenient location of your choice (e.g. C:). Run either
femustart or CPU specific femu.0x0 from CLI. Ctrl+C will stop femu and 
restore original CPU settings. It is possible to run femu from user-startup 
as well.

## Versions

femu.020 - For real 020 and 030 machines and WinUAE 3.5.0 or later (set CPU to 
68020 and enable more compatible and JIT). 

femu.040 - For real 040 machines. Does not work with WinUAE 3.5.0 properly.

femu.080 - Removed because the Vampire has an FPU now.

femustart - Detects CPU and automatically starts correct version.

Two build-time switches change what gets assembled (`vasm -D<FLAG>`,
same convention the `Makefile` already uses for `CPU020`/`CPU040`):

- **`NOMATHLIB`** -- the default and only supported mode for `fadd`/
  `fsub`/`fmul`/`fdiv` and every transcendental: all arithmetic runs
  natively (see Architecture below), with no dependency on
  `mathieeedoubbas.library`/`mathieeedoubtrans.library` at all.
- **`MANTISSA32`** -- opt-in, off by default. Rounds every `fadd`/
  `fsub`/`fmul`/`fdiv` operand to a 32-bit significant mantissa instead
  of the full 64 before computing, trading precision for speed
  (`fdiv` roughly 2.7x faster, `fmul` roughly 1.2x faster; `fadd`/
  `fsub` only marginally faster). Meant for CPU-constrained real
  hardware running something demanding enough to want every cycle back;
  leave it off for anything precision-sensitive.

## License

You can use femu for you own pleasure. There is no guarantee. If femu
corrupts your HDD or burns down your house, responsibility is yours only.
You are responsible of backing up and restoring your files. 

## Architecture

This fork's emulation core (`src/utils/fhandler.asm`, `src/utils/op.asm`,
`src/ops/*.asm`) differs from the original in a few load-bearing ways:

- **No math library dependency.** Every arithmetic op (`fadd`/`fsub`/
  `fmul`/`fdiv`) and every transcendental (`fsin`, `fetox`, `fsqrt`,
  etc.) is computed natively in 68K assembly -- no `jsr` to
  `mathieeedoubbas.library`/`mathieeedoubtrans.library` anywhere on the
  hot path. `MUL64`/`DIV64` (`src/utils/math64.asm`) implement 64-bit
  multiply/divide from 68020 `mulu.l`/plain shift-and-subtract; the
  transcendentals use range reduction plus a Remez-exchange-derived
  minimax polynomial (`src/utils/nativemath.asm`), verified against
  `mpmath`-precision references before being committed to assembly.
- **Native extended (80-bit-equivalent) internal format.** FPn
  registers (`RegFpn`) are stored sign(1):exponent(15):reserved(16),
  then a full 64-bit explicit-integer-bit mantissa -- not the original
  53-bit hidden-bit double format. `fmove.x`/`fmovem.x` are a straight
  byte copy to/from memory; conversion to/from the CPU's own 80-bit
  extended format and to/from `double` (for `fmove.d` and anything that
  still needs it) happens at `src/utils/type.asm`'s boundary helpers.
- **Relaxed-IEEE and opcode fast paths.** `fadd`/`fmul`/`fdiv` check
  once whether both operands are ordinary (finite, nonzero, non-
  denormal) and skip straight to the main computation when so; a
  separate fast path short-circuits multiply/divide by exactly ±1 or a
  power of two. FPCR's single-precision rounding mode (and `fsmul`/
  `fsglmul`/`fsdiv`/`fsgldiv`'s opcode-forced single) take a narrower,
  24-bit-mantissa path that trades one `mulu.l`/`divu.l` for `MUL64`/
  `DIV64`'s full-width work, matching real 68881 single-precision
  semantics exactly for already-single operands.
- **EA-decode fast path.** `GETEAVALUE` (`src/utils/ea.asm`) special-
  cases `Dn`/`(An)`/`(An)+`/`-(An)`/`d16(An)` -- the overwhelming
  majority of real addressing modes -- before falling through to the
  general 68020+ decoder for everything else.
- **Opcode chaining.** `HandleException` peeks at the word immediately
  after the opcode it just emulated; if that word also looks like an
  F-line opcode, it keeps going instead of paying a full trap exit/
  re-entry (`rte` + refault) between back-to-back FPU instructions.
- **`MANTISSA32`** (see Versions above) narrows `fadd`/`fsub`/`fmul`/
  `fdiv`'s internal mantissa to 32 significant bits, independent of and
  alongside the extended-format default -- `FE_FADD_32`/`FE_FMUL_32`/
  `FE_FDIV_32` in `src/ops/fadd.asm`/`fmul.asm`/`fdiv.asm` mirror their
  64-bit counterparts' structure at half the register width.

The Apollo 68080 (`CPU080`/`VECTOR080`) path is a separate story: when
`VECTOR080` is defined, hardware FPU vectors are installed directly and
this software emulator is bypassed for that CPU -- it already has a
real FPU.

### Where to look

- **`CLAUDE.md`** -- the working agreement for this repo: ground truth
  about the codebase, and the workflow this project uses for picking up
  a new performance idea (branch, measure before/after, guard it behind
  a build flag if it's a relaxation, merge on a real win).
- **`BENCHMARK.md`** -- how a change here gets measured: a headless 68K
  core (`bench/`) that runs femu's real, assembled `HandleException`
  with exact cycle counts, since real Amiga hardware/WinUAE/FS-UAE
  don't give you a scriptable one.
- **`ISSUES.md`** -- the original author's per-opcode issue notes.
- **`NEXT.md`** -- current status in one paragraph, and what to do if
  you're picking up a new optimization idea.
- Git history -- every change above was made as its own commit (and,
  for most, its own PR), with the measured before/after numbers in the
  commit message. That record is the detailed design log; this file
  only tracks the current, settled state.
