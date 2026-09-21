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

## License

You can use femu for you own pleasure. There is no guarantee. If femu
corrupts your HDD or burns down your house, responsibility is yours only.
You are responsible of backing up and restoring your files. 

## Performance Optimization Plan

Software FPU emulation is never going to be fast, but the current
implementation leaves a lot on the table: nearly every arithmetic and
transcendental opcode calls out to `mathieeedoubbas.library` /
`mathieeedoubtrans.library` over `jsr`, every trap pays for a full
register save/restore and `rte` even when the next instruction is another
FPU op, and the internal double-precision format forces a pack/unpack
round trip on every value that crosses the register boundary. This section
tracks the plan to fix that.

Three companion docs go with this plan:

- **`CLAUDE.md`** — the working agreement: goals, and low-level/assembly
  practices for this repo. Read it before starting any row below.
- **`BENCHMARK.md`** — the concrete, host-runnable way we measure a
  speedup (a headless 68K core, not real hardware — see that doc for why).
- **`NEXT.md`** — a one-paragraph kickoff, meant to bootstrap a fresh
  session without dragging this whole history forward.

### Workflow

For each row in the checklist below:

1. Branch off `master` as `perf/<id>-<slug>`.
2. Implement that one idea, and nothing else.
3. Benchmark before/after per `BENCHMARK.md`.
4. **Actual improvement** (net cycle win, no correctness regression) →
   merge to `master`, mark the row ✅, record the measured delta.
   **No win, or a regression** → mark the row ❌, ~~strike the idea~~,
   write one sentence on why, leave the branch pushed and **unmerged —
   never deleted**, in case a later dependency changes the answer.
5. Return to `master`, pick the next row whose dependencies are ✅.

### Checklist

| # | Idea | Depends on | Status | Branch | Result |
|---|------|------------|--------|--------|--------|
| 0 | Build the `bench/` cycle-counting harness (Musashi-based) and port golden test vectors from `ftest.asm`, fixing its dead-code bug along the way | — | ✅ Done | `claude/keen-mendel-3hb6vs` | Working end-to-end against `master`: `bench/` assembles real femu (both `femu.020` and `femu.020m`/`NOMATHLIB` builds) via vendored `vasm`, runs it under a headless Musashi 68020 core, and reports per-opcode cycle counts + correctness for 24 opcodes ported from `ftest.asm`. Coverage is intentionally partial for a first landing — see "Current coverage and known limits" in `bench/README.md` (register-direct addressing only, 68020 only, no NaN/Inf/denormal vectors yet) — extending it is fair game for later branches, not a blocker. |
| 1 | Implement real native mantissa multiply/divide (`MUL64`/`DIV64`) and finish `FE_FADD`/`FE_FMUL`/`FE_FSUB`/`FE_FDIV` under `NOMATHLIB` — today `FE_FMUL` multiplies mantissas with `ADD64`, which is simply wrong | 0 | ✅ Done | `claude/keen-mendel-3hb6vs` | `MUL64` (hardware `mulu.l`-based 64x64→128 schoolbook multiply) and `DIV64` (54-iteration restoring binary division) landed in `math64.asm`; `FE_FMUL`/`FE_FDIV` rewritten on top of them with correct round-to-nearest-even (round+sticky bits, tie-to-even) and bit-exact vs. `bench/`'s host-double reference on every vector, including negative operands and both mantissa-overflow cases. `FE_FADD`/`FE_FSUB` were already correct going in (`ADD64`-based, not the `FE_FMUL` bug), so left alone. `NOMATHLIB` cycle cost: `fmul` ~1143–1177 (was 642, but that number was a `(stub)` row — see `bench/README.md` — not a real baseline to beat), `fdiv` ~4415–4679 (was 634, same caveat). `fdiv`'s cost is dominated by the one-bit-at-a-time division loop; a hardware-`divu.l`-seeded algorithm is a good candidate for its own future row rather than scope-creeping into this one. |
| 2 | Make `NOMATHLIB` the default: drop the `mathieeedoubbas.library`/`mathieeedoubtrans.library` calls for `fadd`/`fsub`/`fmul`/`fdiv`/`fcmp`/`fneg`/`fabs`, eliminating the library `jsr` and its OpenLibrary dependency | 1 | ✅ Done | `claude/keen-mendel-3hb6vs` | `fcmp`/`fneg`/`fabs` were already library-free. Unwrapped `fadd`/`fsub`/`fmul`/`fdiv` from their `ifd NOMATHLIB`/`else` split so the default build (no `-DNOMATHLIB`) now always uses `FE_FADD`/`FE_FSUB`/`FE_FMUL`/`FE_FDIV` instead of `jsr`ing to `mathieeedoubbas.library`; `NOMATHLIB` still gates the not-yet-native ops (`fint`/`fintrz`, transcendentals) as before, so the flag isn't fully retired, just no longer needed for the arithmetic ops. `bench/`'s `femu.020 (library)` variant now measures real cycles for these four ops instead of a `(stub)` `jsr` row (previously not a real baseline per `BENCHMARK.md`), landing at the same bit-exact numbers `femu.020m` already had: `fadd` 914, `fsub` 912, `fmul` 1143–1177, `fdiv` 4415–4679. `fint`/`fintrz`/transcendentals and the `femu.020m` build are untouched. Assembled clean for `CPU020`/`CPU040` × with/without `NOMATHLIB` via vendored `vasm`. |
| 3 | Relaxed-IEEE fast path: skip Inf/NaN/denormal special-casing when it's cheap to prove the operands don't need it, only fall through to the correct slow path when a check (already mostly present, e.g. the `$7ff` exponent test) says otherwise — no silent wrong answers, see `CLAUDE.md` | 1 | 🔲 Not started | `perf/03-relaxed-ieee` | |
| 4 | Native internal representation: carry FP values internally in a format matching the CPU's 80-bit extended register (explicit integer bit, 16-bit exponent) instead of packed IEEE double, so `fmove` to/from an FPn register needs no hidden-bit insert/strip; convert to IEEE double/single only when writing to memory in that format | 1 | 🔲 Not started | `perf/04-native-extended-repr` | |
| 5 | Force-single-precision fast path: when FPCR rounding precision or the opcode (`fsadd`/`fsmul`/...) says single, do 32-bit mantissa math instead of 64-bit — halves the work in `ALIGNEXPONENT`/`NORMALIZE` and avoids `MUL64`/`DIV64` for the common case | 1 | 🔲 Not started | `perf/05-single-precision-fastpath` | |
| 6 | FPU-opcode chaining: before `POSTHANDLEEXCEPTION`/`rte`, peek at the instruction word(s) after the one just emulated; if it's another F-line opcode, loop back into `EmulateInstruction` directly instead of paying full exception entry/exit again | 0 | 🔲 Not started | `perf/06-opcode-chaining` | |
| 7 | Trim the trap prologue/epilogue: `movem.l d0-d7/a0-sp` saves/restores all 15 registers on every trap; save only what the specific handler actually clobbers | 0, 6 | 🔲 Not started | `perf/07-lean-trap-frame` | |
| 8 | EA-decode fast path in `src/utils/ea.asm` for the handful of addressing modes real code overwhelmingly uses (`Dn`, `(An)`, `(An)+`, `-(An)`, `d16(An)`), falling through to the existing general decoder for everything else | 0 | 🔲 Not started | `perf/08-ea-fastpath` | |
| 9 | Fast paths for cheap special cases: `ftwotox`/`ftentox` with an integer exponent (bump the exponent field, no `Pow()` call), `fetox`/`flogn` at 0/1, multiply/divide by 0/1/power-of-two, `fsqrt` at 0/1 | 1 | 🔲 Not started | `perf/09-transcendental-fastpaths` | |
| 10 | Native transcendentals: implement `facos`/`fasin`/`fatan`/`fcos`/`fcosh`/`fsin`/`fsinh`/`ftan`/`ftanh`/`fetox`/`flogn`/`flog2`/`flog10`/`fsincos` without `mathieeedoubtrans.library`, building on the native representation from #4 | 1, 4 | 🔲 Not started | `perf/10-native-transcendentals` | |
| 11 | Fix `fmovem` bulk register move (flagged buggy in a TODO; hardware `fmovem` "fixes problems" per the same note) — correctness fix that's also a hot path for context-heavy code | 0 | 🔲 Not started | `perf/11-fmovem-fix` | |

See `ISSUES.md` for the original author's per-opcode issue notes — several
rows above trace directly back to entries there (e.g. "calls
MathIeeeDoubTrans" for nearly every transcendental).
