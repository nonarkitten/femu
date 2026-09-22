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

The table below is deliberately terse — GitHub's file view is narrow, and a
paragraph-per-cell table becomes an unreadable wall of horizontal scroll.
Each row links to its full write-up (idea, dependencies, and the measured
result) in [Checklist details](#checklist-details) below.

| # | Idea | Depends on | Status | Branch |
|---|------|:----------:|--------|--------|
| [0](#row-0) | Build the `bench/` cycle-counting harness | — | ✅ Done | `claude/keen-mendel-3hb6vs` |
| [1](#row-1) | Native `MUL64`/`DIV64` + real `FE_FMUL`/`FE_FDIV` under `NOMATHLIB` | 0 | ✅ Done | `claude/keen-mendel-3hb6vs` |
| [2](#row-2) | Make `NOMATHLIB` the default | 1 | ✅ Done | `perf/02-nomathlib-default` |
| [3](#row-3) | Relaxed-IEEE fast path (skip Inf/NaN/denormal checks when provably safe) | 1 | ✅ Done | `claude/keen-mendel-3hb6vs` |
| [4](#row-4) | Native extended (80-bit-equivalent) internal representation | 1 | ✅ Done | `claude/keen-mendel-3hb6vs` |
| [5](#row-5) | Force-single-precision fast path | 1 | ✅ Done (`fmul`/`fdiv` only) | `claude/keen-mendel-3hb6vs` |
| [6](#row-6) | FPU-opcode chaining (skip trap exit/re-entry between back-to-back ops) | 0 | ✅ Done | `perf/06-opcode-chaining` |
| [7](#row-7) | ~~Trim the trap prologue/epilogue (save only what's clobbered)~~ | 0, 6 | ❌ Not viable as scoped | `perf/07-lean-trap-frame` |
| [8](#row-8) | EA-decode fast path for the common addressing modes | 0 | 🔲 Not started | `perf/08-ea-fastpath` |
| [9](#row-9) | Fast paths for cheap transcendental special cases | 1 | 🔲 Not started | `perf/09-transcendental-fastpaths` |
| [10](#row-10) | Native transcendentals (drop `mathieeedoubtrans.library`) | 1, 4 | 🔲 Not started | `perf/10-native-transcendentals` |
| [11](#row-11) | Fix `fmovem` bulk register move | 0 | 🔲 Not started | `perf/11-fmovem-fix` |

### Checklist details

<a id="row-0"></a>
#### #0 — Build the `bench/` cycle-counting harness

- **Idea:** Build the `bench/` cycle-counting harness (Musashi-based) and
  port golden test vectors from `ftest.asm`, fixing its dead-code bug along
  the way.
- **Depends on:** —
- **Status:** ✅ Done
- **Branch:** `claude/keen-mendel-3hb6vs`
- **Result:** Working end-to-end against `master`: `bench/` assembles real
  femu (both `femu.020` and `femu.020m`/`NOMATHLIB` builds) via vendored
  `vasm`, runs it under a headless Musashi 68020 core, and reports
  per-opcode cycle counts + correctness for 24 opcodes ported from
  `ftest.asm`. Coverage is intentionally partial for a first landing — see
  "Current coverage and known limits" in `bench/README.md`
  (register-direct addressing only, 68020 only, no NaN/Inf/denormal
  vectors yet) — extending it is fair game for later branches, not a
  blocker.

<a id="row-1"></a>
#### #1 — Native `MUL64`/`DIV64` + real `FE_FMUL`/`FE_FDIV`

- **Idea:** Implement real native mantissa multiply/divide (`MUL64`/`DIV64`)
  and finish `FE_FADD`/`FE_FMUL`/`FE_FSUB`/`FE_FDIV` under `NOMATHLIB` —
  today `FE_FMUL` multiplies mantissas with `ADD64`, which is simply wrong.
- **Depends on:** 0
- **Status:** ✅ Done
- **Branch:** `claude/keen-mendel-3hb6vs`
- **Result:** `MUL64` (hardware `mulu.l`-based 64x64→128 schoolbook
  multiply) and `DIV64` (54-iteration restoring binary division) landed in
  `math64.asm`; `FE_FMUL`/`FE_FDIV` rewritten on top of them with correct
  round-to-nearest-even (round+sticky bits, tie-to-even) and bit-exact vs.
  `bench/`'s host-double reference on every vector, including negative
  operands and both mantissa-overflow cases. `FE_FADD`/`FE_FSUB` were
  already correct going in (`ADD64`-based, not the `FE_FMUL` bug), so left
  alone. `NOMATHLIB` cycle cost: `fmul` ~1143–1177 (was 642, but that
  number was a `(stub)` row — see `bench/README.md` — not a real baseline
  to beat), `fdiv` ~4415–4679 (was 634, same caveat). `fdiv`'s cost is
  dominated by the one-bit-at-a-time division loop; a hardware-`divu.l`-
  seeded algorithm is a good candidate for its own future row rather than
  scope-creeping into this one.

<a id="row-2"></a>
#### #2 — Make `NOMATHLIB` the default

- **Idea:** Make `NOMATHLIB` the default: drop the
  `mathieeedoubbas.library`/`mathieeedoubtrans.library` calls for
  `fadd`/`fsub`/`fmul`/`fdiv`/`fcmp`/`fneg`/`fabs`, eliminating the library
  `jsr` and its OpenLibrary dependency.
- **Depends on:** 1
- **Status:** ✅ Done
- **Branch:** `perf/02-nomathlib-default`
- **Result:** `fcmp`/`fneg`/`fabs` were already library-free. Unwrapped
  `fadd`/`fsub`/`fmul`/`fdiv` from their `ifd NOMATHLIB`/`else` split so
  the default build (no `-DNOMATHLIB`) now always uses
  `FE_FADD`/`FE_FSUB`/`FE_FMUL`/`FE_FDIV` instead of `jsr`ing to
  `mathieeedoubbas.library`; `NOMATHLIB` still gates the not-yet-native ops
  (`fint`/`fintrz`, transcendentals) as before, so the flag isn't fully
  retired, just no longer needed for the arithmetic ops. `bench/`'s
  `femu.020 (library)` variant now measures real cycles for these four ops
  instead of a `(stub)` `jsr` row (previously not a real baseline per
  `BENCHMARK.md`), landing at the same bit-exact numbers `femu.020m`
  already had: `fadd` 914, `fsub` 912, `fmul` 1143–1177, `fdiv`
  4415–4679. `fint`/`fintrz`/transcendentals and the `femu.020m` build are
  untouched. Assembled clean for `CPU020`/`CPU040` × with/without
  `NOMATHLIB` via vendored `vasm`.

<a id="row-3"></a>
#### #3 — Relaxed-IEEE fast path

- **Idea:** Relaxed-IEEE fast path: skip Inf/NaN/denormal special-casing
  when it's cheap to prove the operands don't need it, only fall through
  to the correct slow path when a check (already mostly present, e.g. the
  `$7ff` exponent test) says otherwise — no silent wrong answers, see
  `CLAUDE.md`.
- **Depends on:** 1
- **Status:** ✅ Done
- **Branch:** `claude/keen-mendel-3hb6vs`
- **Result:** Added a single unsigned range check per operand
  (`(exp-1) < 2046`, i.e. "finite, nonzero, not a denormal") right after
  exponent extraction in `FE_FADD`/`FE_FMUL`/`FE_FDIV`; when both pass,
  jumps straight past the existing Inf/NaN/zero ladder into the real
  computation. The range check is an exact complement of the ladder's own
  conditions, so it can never take the fast path when the ladder would
  have done something — verified bit-exact (not just cycle-matched)
  against `bench/`'s host-double reference on 9 new Inf/NaN/zero vectors,
  with results identical before/after this change. Honest tradeoff: the
  ordinary (fast) path gets ~2 cycles faster per op; the rare special-case
  path pays ~14-26 cycles extra for the failed probe. Kept anyway — real
  FPU workloads are overwhelmingly ordinary values, and it's a real,
  zero-regression, zero-added-risk win on the path that matters, not a
  free lunch. Denormals are still silently treated as zero (pre-existing,
  unchanged by this row — see `ISSUES.md`; actual denormal arithmetic
  support would be a much larger, separate undertaking).

<a id="row-4"></a>
#### #4 — Native extended internal representation

- **Idea:** Native internal representation: carry FP values internally in
  a format matching the CPU's 80-bit extended register (explicit integer
  bit, 16-bit exponent) instead of packed IEEE double, so `fmove` to/from
  an FPn register needs no hidden-bit insert/strip; convert to IEEE
  double/single only when writing to memory in that format.
- **Depends on:** 1
- **Status:** ✅ Done
- **Branch:** `claude/keen-mendel-3hb6vs`
- **Result:** Full rewrite, not the narrower `fmovem`-only follow-up the
  design pass (`DESIGN-04-native-extended-repr.md`) recommended — the user
  explicitly chose the bigger/riskier scope for genuine 80-bit-equivalent
  precision, not just perf, after being shown the tradeoffs below.
  `RegFpn` is now 16×12 bytes (sign:1/exponent:15/reserved:16/
  mantissa:64-explicit-bit), byte-identical to the real 68881 `.x` memory
  format. Touched every op that reads or writes an FP register:
  `fadd`/`fsub`/`fmul`/`fdiv`/`fcmp` rewritten natively for the new
  exponent width and explicit-bit mantissa (no more hidden-bit
  insert/strip — genuinely simpler there, as the design doc predicted);
  `fneg`/`fabs`/`fscale`/`fgetexp`/`fgetman`/`ftst` mechanically widened;
  `fmovecr`/`fint`/`fintrz`/all still-library-based transcendentals
  wrapped with new `InternalToDouble`/`DoubleToInternal` conversion calls
  (`type.asm`) rather than rewritten, to stay in scope.

  **Measured, not guessed** (`bench/`, register-direct vectors + the
  `fmove`/`fmovem` memory-operand probe, before/after, bit-exact against
  host-double reference on every vector including Inf/NaN/zero):

  - `fmovem.x` (4 registers): **1369-1457 → 953 cycles**, the one clear,
    unambiguous win this row's whole idea was banking on — the
    per-register `ExtendedToDouble`/`DoubleToExtended` `jsr` is gone
    entirely, replaced by a straight `movem.l`.
  - `fmove.x` reg↔mem: **732-844 → 628-714**, faster, now that no
    conversion happens at all (also fixes a real pre-existing rounding bug
    in the old `ExtendedToDouble`, found during `#4`'s design pass —
    extended `1.5` came back as `1.5000000001164082`).
  - `fmove.d` reg↔mem: **605-695 → 769-859**, slower by about the same
    amount `fmove.x` improved — the conversion cost relocated, exactly as
    the design doc predicted, not eliminated.
  - `fadd`/`fsub` (register-to-register): **912/910 → 961/953**, ~5%
    *slower* — the old double-format `NEG64`+`ADD64`+`ABS64` "convert to
    2's complement, add, take sign+magnitude" trick relied on a spare top
    bit (53-bit mantissa in a 64-bit pair) that a genuine 64-bit
    mantissa's *always-set* explicit integer bit no longer leaves free;
    replaced with explicit same-sign/different-sign branching, which
    costs a bit more.
  - `fmul`: **1141-1175 → 1114-1149**, essentially a wash (marginally
    faster in most cases) — `MUL64` doesn't care about operand width, and
    the product-extraction is actually simpler (register-aligned, no more
    memory-buffer `bfextu` at odd offsets).
  - `fdiv`: **4413-4677 → 5227-5693**, ~15-20% slower — `DIV64` now runs
    64 iterations instead of 54 (a 53→64-bit mantissa needs more bits of
    quotient) plus a 65th "phantom" iteration for the round bit, since a
    64-bit accumulator has zero spare headroom left to fold that bit in
    for free the way the old 53-bit version could.

  So: reg-to-reg arithmetic did **not** get "significantly faster" as
  originally hoped (the premise didn't hold — see `#4`'s design doc,
  confirmed here) — `fadd`/`fsub`/`fdiv` got measurably slower, `fmul`
  roughly a wash, and the real, substantial win landed exactly where the
  design pass predicted it would: `fmovem`. What this row buys instead is
  real: femu's internal FP values now carry genuine ~80-bit extended
  precision (a 64-bit explicit mantissa) rather than being silently capped
  at IEEE double's 53 bits for every register-to-register operation,
  matching real 68881 hardware behavior more closely. Two bugs found and
  fixed along the way, both now load-bearing rather than edge cases once
  this format carries every op: the `ExtendedToDouble` rounding bug above,
  and `InternalToDouble`/`DoubleToInternal` (its replacements) needed real
  round-to-nearest-even added when narrowing to double (the old code only
  truncated — fine for the rare `.x` round-trip it used to serve, a
  measurable bias now that transcendentals/`fmove.d`/etc. all go through
  it constantly).

<a id="row-5"></a>
#### #5 — Force-single-precision fast path

- **Idea:** Force-single-precision fast path: when FPCR rounding
  precision or the opcode (`fsadd`/`fsmul`/...) says single, do 32-bit
  mantissa math instead of 64-bit — halves the work in
  `ALIGNEXPONENT`/`NORMALIZE` and avoids `MUL64`/`DIV64` for the common
  case.
- **Depends on:** 1
- **Status:** ✅ Done (`fmul`/`fdiv` only)
- **Branch:** `claude/keen-mendel-3hb6vs`
- **Result:** Scoped to `fmul`/`fdiv` — the two ops `MUL64`/`DIV64` made
  slower after `#4` and the ones the checklist description explicitly
  calls out for avoiding them; `fadd`/`fsub` deferred (see below), by
  explicit user direction after being shown the tradeoff.

  **The relaxation, stated up front and chosen by the user over the
  hardware-exact alternative** (`AskUserQuestion`, "narrow operands, real
  speedup" vs "always hardware-correct, no MUL64/DIV64 avoidance"): both
  operands are rounded to a 24-bit significant mantissa *before*
  computing, not after — real 68881 `fsmul`/`fsdiv`/FPCR-single compute at
  full extended precision and round only the final result. This is
  bit-exact to real hardware whenever both operands are already clean
  single values (chained `fs*`, or anything that passed through
  `fmove.s`) — verified against an independent from-scratch reference
  (float32 multiply: 0/300000 mismatches; the division algorithm below:
  0/300000 random + 27 targeted edge cases against an exact `Fraction`-
  based reference) — but can differ by up to a few ULP from "compute full
  then round" hardware when an operand carries precision below the 24th
  bit.

  `FE_FMUL_SINGLE`/`FE_FDIV_SINGLE` (`src/ops/fmul.asm`/`fdiv.asm`)
  duplicate the Inf/NaN/zero special-case ladder rather than sharing it
  with `FE_FMUL`/`FE_FDIV` (same per-op-not-shared style as the rest of
  the file) — necessarily so, since vasm's local-label scoping is per
  enclosing global label, not per macro invocation, and
  `FMULHANDLER`/`FDIVHANDLER`'s runtime FPCR-check path invokes *both* the
  extended and single macros from the same handler label when FPCR isn't
  forcing single. `FE_FMUL_SINGLE` replaces `MUL64`'s four `mulu.l`s with
  one (24×24-bit fits a single hardware multiply). `FE_FDIV_SINGLE`
  replaces `DIV64`'s 64+1-iteration restoring-division loop with one
  hardware `divu.l`: the 64-bit scaled dividend `dst24<<31` is built
  directly in the `Dr:Dq` pair with no multi-word shift (`Dq` is just
  `dst24` shifted left 31 within one register — everything above bit0
  naturally shifts out, which is exactly the low half of that 64-bit
  shift; `Dr` is `dst24>>1`), verified overflow-safe for every in-range
  operand pair (worst case `(2^24-1)*2^31/2^23 = 2^32-256`, computed
  exactly, not estimated). The divisor's own rounding-overflow case
  subtracts 1 from the combined exponent rather than adding (opposite of
  the dividend/multiply case, since it's in the denominator) — a real
  sign-flip bug caught by the edge-case verification before any assembly
  was written.

  **Measured** (`bench/`'s dedicated `fsmul`/`fsglmul`/`fsdiv`/`fsgldiv`/
  FPCR-single probe, register-direct, clean-single operands chosen to
  force real 24-bit rounding on both the operand-round and result-round
  steps): `fmul` (extended, unchanged path) 1149 → 1178 (+29, the new
  unconditional FPCR-precision runtime check on the plain-opcode path) but
  `fsmul`/`fsglmul` **957 cycles** and FPCR-forced-single `fmul` **976
  cycles** — a genuine ~19% win over extended `fmul`, not just a wash.
  `fdiv` (extended) 5227-5693 → 5256-5722 (same +29 dispatch tax) but
  `fsdiv`/`fsgldiv` **1000 cycles** and FPCR-forced-single `fdiv` **1019
  cycles** — roughly **5x faster** than extended `fdiv`, the single
  biggest win in this row and squarely the "a lot faster" the user
  expected to offset `#4`'s `fdiv` regression. All existing
  register-direct vectors still bit-exact (`MATCH`) on both `femu.020` and
  `femu.020m` builds — the new dispatch check doesn't change any existing
  behavior, only adds a branch. `fadd`/`fsub` single-precision fast paths
  are NOT implemented — `FE_FADD`/`FE_FSUB` are already O(1) (branching,
  not an iterative loop), so halving `ALIGNEXPONENT`/`NORMALIZE`'s width
  saves a handful of instructions at best, not a `MUL64`/`DIV64`-class
  win; left as a candidate future row if a future pass wants it, not
  blocking this one.

  **A real vasm bug found and worked around, worth knowing if this
  pattern comes up again**: calling a macro that defines local labels from
  *both* branches of an `ifnb`/`else` block, when that macro is invoked
  more than once across a file (as `FMULHANDLER`/`FDIVHANDLER` now are,
  once per handler-label block), sends this vasm build into unbounded
  memory allocation instead of a clean error — reproduced independently
  with a minimal macro-only test file, unrelated to anything else in this
  row. Worked around by keeping `FE_FMUL`/`FE_FMUL_SINGLE` (and the `fdiv`
  equivalents) each invoked exactly once per macro expansion (the `ifnb`
  block only selects a branch target, the shared code after it calls the
  macro once) — see `FMULHANDLER`'s comment in `src/ops/fmul.asm`. A
  second, narrower vasm quirk in the same area: `ifnb` on a macro
  parameter that's blank via an *explicit leading comma* in one call site
  (`MACRO ,arg`) and blank via plain omission in another call site of the
  *same* macro, checked across those two invocations, also triggers the
  same runaway-allocation bug — worked around by never leading with a
  blank comma (`MACRO single` instead of `MACRO ,single`), reordering the
  parameter position so the single-precision flag is always `\1`, passed
  as a bare token or omitted, never comma-blanked.

Fresh `perf/*`-style row candidates surfaced while working #5, not
started, just noted per `CLAUDE.md`'s "note them, don't fix them inline":

- `fadd`/`fsub` single-precision fast path (see `#5`'s row above for why
  it's a much smaller win than `fmul`/`fdiv` — a candidate for its own row
  only if a future pass specifically wants it).

<a id="row-6"></a>
#### #6 — FPU-opcode chaining

- **Idea:** Before `POSTHANDLEEXCEPTION`/`rte`, peek at the instruction
  word(s) after the one just emulated; if it's another F-line opcode,
  loop back into `EmulateInstruction` directly instead of paying full
  exception entry/exit again.
- **Depends on:** 0
- **Status:** ✅ Done
- **Branch:** `perf/06-opcode-chaining`
- **Result:** `HandleException` (`src/utils/fhandler.asm`) now loops:
  after `jsr EmulateInstruction` returns, every handler has already
  advanced `FAULTPC` (the real 68K register `a4`) past its own
  opcode/extension/EA words on the way out, so `(FAULTPC)` is exactly the
  next instruction the CPU would fetch on `rte`. A single
  `move.l (FAULTPC),INSTRUCTION` + `bfextu INSTRUCTION{0:4},d0` +
  `cmp.b #$f,d0` (the same top-nibble test the CPU itself effectively used
  to land here) decides: F-line again → `beq.s` straight back into
  `EmulateInstruction` with no `rte`/re-trap; anything else → falls
  through to the original `POSTHANDLEEXCEPTION`/`rte`, unchanged. No
  `ifd`/`ifnd` needed — `FAULTPC`/`INSTRUCTION` are the same register
  equates on every `STACK020`/`STACK040`/`STACK080` build, and CPU080's
  hardware-direct vectors (`DirectOpVectorsAligned`) don't go through
  `HandleException` at all so are untouched; the software-fallback subset
  CPU080 *does* route through `HandleException` benefits too.

  **A real, and non-obvious, bug found and fixed along the way**: every
  existing single-opcode bench probe (the main `vectors/ops.txt` loop,
  `run_fmove_probe`, `run_fsmul_probe`) packed its test opcodes
  back-to-back with zero gap and relied on the *real CPU* re-trapping on
  the next one to naturally stop at `resume_pc = test_pc+4` — harmless
  before this row, since only a real trap could ever "see" the next
  slot's bytes, but with chaining live the peek itself reads straight
  into the next queued test's opcode and (being real F-line) happily
  chains into it, so every existing probe would have started silently
  executing (and mis-timing) its neighbor's opcode as part of the
  "current" one's cycle count. Fixed by placing each 4-byte test opcode
  `SLOT_STRIDE` (8) bytes apart instead of 4, leaving the gap zeroed (not
  F-line) — verified this changes **zero** existing numbers (see below)
  since the harness only reads memory, never re-lays it out based on
  opcode length.

  **Measured** (`bench/`, `femu.020`/`femu.020m`, register-direct — full
  numbers in `bench/baseline/020.txt`): every existing single-op vector,
  `fmove`/`fmovem` probe row, and `fsmul`/`fsdiv` probe row got **exactly
  +22 cycles**, flat, regardless of op (`fadd` 961→983, `fmul` 1178→1200,
  `fdiv` 5722→5744, `fabs` 626→648, ...) — the fixed cost of the new
  peek-and-compare on the path that *doesn't* chain (every one of these is
  followed by the zeroed gap, so none of them do) — and zero correctness
  regressions (still bit-exact/`MATCH` on every vector, `flog2`'s
  pre-existing 1-ULP `DIFFER` unchanged). A new dedicated probe
  (`bench/src/chain_probe.asm` + `run_chain_probe`) places real,
  un-padded back-to-back opcodes to measure the actual win: two chained
  `fadd`s **1904 → 1661** (−243, −12.8%), `fadd` then `fmul` chained
  **2103 → 1860** (−243, −11.6%), three chained `fadd`s **2853 → 2345**
  (−508, −17.8%, i.e. ~2× the two-op saving, since a chain of 3 skips
  *two* trap exits instead of one), and the regression case — one real
  `fadd` immediately followed by a real `nop` in memory — correctly does
  **not** chain (resumes at `test_pc+4`, not `+8`), paying only the flat
  +22 tax (929→951) exactly like an ordinary standalone op, proving the
  peek can tell a real neighboring FPU opcode from ordinary code and
  never over-consumes. The arithmetic is clean and consistent both ways:
  each *avoided* trap exit/re-entry is worth ~287 cycles (`243 + 2×22`
  for the pair; `508 + 3×22` over two boundaries ≈ `2×287`), so every
  additional opcode folded into a chain nets **~265 cycles** (287 saved −
  22 tax) on top of whatever the op itself costs — the win scales with
  how many FPU opcodes actually run back-to-back in real code, not with
  which opcode they are (fixed absolute savings, so proportionally
  largest for cheap ops like `fadd`/`fmove`, smallest for
  `fdiv`/transcendentals).

  Honest tradeoff, not mentioned in the original idea and worth flagging:
  `PREHANDLEEXCEPTION` disables interrupts (mask 7) for the whole chain,
  not just one opcode — a long run of back-to-back FPU instructions now
  holds interrupts off proportionally longer than before (previously
  bounded by one opcode's worth of work); not a correctness issue and not
  gated behind a flag (real 68881 hardware doesn't take interrupts
  mid-instruction either), but a real latency cost for
  interrupt-sensitive code that leans on dense FPU op sequences, worth
  knowing if it ever comes up.

<a id="row-7"></a>
#### #7 — Trim the trap prologue/epilogue

- **Idea:** ~~`movem.l d0-d7/a0-sp` saves/restores all 15 registers on
  every trap; save only what the specific handler actually clobbers.~~
- **Depends on:** 0, 6
- **Status:** ❌ Not viable as scoped
- **Branch:** `perf/07-lean-trap-frame`
- **Result:** Investigated, not implemented — no code changed beyond a
  comment recording the finding (`src/utils/fhandler.asm`, above
  `PREHANDLEEXCEPTION`), since the saving isn't reachable without breaking
  an invariant the rest of the emulator depends on.

  `ea.asm`'s `GETEAVALUE`/`GetEa`/`ADDAN` reach any of the 15 general
  registers by a *runtime*-computed offset —
  `(OSTACKAN,STACKFRAME,dN.w)`, `OSTACKAN`/`OSTACKDN` fixed at `-32`/`-64`
  from `STACKFRAME` — into exactly the frame `PREHANDLEEXCEPTION`'s
  `movem.l d0-d7/a0-sp,-(sp)` lays down. Any FPU opcode with a memory
  operand can name any of `a0`-`a6`/`d0`-`d7` in its EA extension word, so
  the *save* side can never be narrowed below the full 15-register set
  without already having decoded the instruction that determines which
  register that is — a chicken-and-egg the shared, one-prologue-for-every-
  opcode design can't resolve.

  Audited whether the "save only what the handler clobbers" framing still
  gives a real, bounded win for the register-to-register form specifically
  (no EA decode at all, so no runtime-dependent register): confirmed by
  grep across every `src/ops/*.asm` that `fadd`/`fsub`/`fmul`/`fdiv`/
  `fcmp`/`fabs`/`fneg`/`ftst`/`fscale`/`fgetexp`/`fgetman` (and their
  `fs*`/`fd*` precision-forced siblings, which share the same handler
  code) never reference `a0`/`a2`/`a3`/`a6` anywhere in their own code or
  in the macros they call (`MOVEFPNTODN`/`MOVEDNTOFPN`/`SETCC`/the `FE_*`
  math macros all stay within `d0`-`d6`/`a1`) — but only when the
  instruction's source-specifier bit (bit 14) says "FPm register", not
  memory; the identical handler code reached via the EA-to-reg path
  unconditionally needs `GetEa` (`a0`) and the full `OSTACKAN` image
  regardless of which op it is, and transcendentals reached through the
  same dispatch table (e.g. `fsin fp0,fp0`, also bit14=0) still need `a6`
  for the library call. So a real skip is only safe for that narrower
  reg-to-reg, non-transcendental subset, decided per-instruction — which,
  under checklist #6's opcode chaining, means per chain iteration, since a
  single prologue/epilogue can now span several different opcodes.

  That narrower version doesn't pay for itself once you try to build it:
  `movem.l ...,-(sp)` only reserves stack space (4 bytes) for registers
  actually present in its transfer list, so omitting `a0`/`a2`/`a3`/`a6`
  from the list also shrinks the frame by 16 bytes — but `OSTACKAN`/
  `OSTACKDN` index every register's slot by its fixed 68K register number
  (`STACKFRAME + OSTACKAN + regnum*4`), so those four slots still have to
  exist at their normal fixed offsets for any later-in-the-chain
  instruction that *does* need them, or for `POSTHANDLEEXCEPTION`'s
  restore (unconditional today, and made conditional only at the cost of
  tracking a reduced/full flag through the whole chain). Gap-filling the
  skipped slots to keep those fixed offsets intact (e.g. `subq.l #4,sp`
  per skipped register) costs about what the `move.l aN,-(sp)` it was
  meant to avoid did in the first place — the entire saving evaporates
  once the frame's fixed-offset addressing (load-bearing for `GETEAVALUE`/
  `ADDAN` everywhere) is kept intact, which it must be for correctness.

  Real per-handler register trimming needs the frame's addressing scheme
  itself to stop being "every register at a fixed absolute offset
  regardless of which ones are actually live for this opcode" — that's
  `#8`'s territory (a fast EA-decode path for the common addressing modes
  could plausibly get away with its own smaller, fixed-shape frame that
  doesn't need the general `OSTACKAN` lookup at all), not a standalone
  edit here. Restated: `#7` is effectively blocked on `#8` landing first,
  not just on `0`/`6` as the checklist's `Depends on` column currently
  says — left as-is rather than edited, since the dependency notation is
  informative context for a future session, not a hard gate the workflow
  enforces.

<a id="row-8"></a>
#### #8 — EA-decode fast path

- **Idea:** EA-decode fast path in `src/utils/ea.asm` for the handful of
  addressing modes real code overwhelmingly uses (`Dn`, `(An)`, `(An)+`,
  `-(An)`, `d16(An)`), falling through to the existing general decoder for
  everything else.
- **Depends on:** 0
- **Status:** 🔲 Not started
- **Branch:** `perf/08-ea-fastpath`
- **Result:** —

<a id="row-9"></a>
#### #9 — Transcendental fast paths for cheap special cases

- **Idea:** Fast paths for cheap special cases: `ftwotox`/`ftentox` with
  an integer exponent (bump the exponent field, no `Pow()` call),
  `fetox`/`flogn` at 0/1, multiply/divide by 0/1/power-of-two, `fsqrt` at
  0/1.
- **Depends on:** 1
- **Status:** 🔲 Not started
- **Branch:** `perf/09-transcendental-fastpaths`
- **Result:** —

<a id="row-10"></a>
#### #10 — Native transcendentals

- **Idea:** Implement `facos`/`fasin`/`fatan`/`fcos`/`fcosh`/`fsin`/
  `fsinh`/`ftan`/`ftanh`/`fetox`/`flogn`/`flog2`/`flog10`/`fsincos`
  without `mathieeedoubtrans.library`, building on the native
  representation from `#4`.
- **Depends on:** 1, 4
- **Status:** 🔲 Not started
- **Branch:** `perf/10-native-transcendentals`
- **Result:** —

<a id="row-11"></a>
#### #11 — Fix `fmovem` bulk register move

- **Idea:** Fix `fmovem` bulk register move (flagged buggy in a TODO;
  hardware `fmovem` "fixes problems" per the same note) — correctness fix
  that's also a hot path for context-heavy code.
- **Depends on:** 0
- **Status:** 🔲 Not started
- **Branch:** `perf/11-fmovem-fix`
- **Result:** —

See `ISSUES.md` for the original author's per-opcode issue notes — several
rows above trace directly back to entries there (e.g. "calls
MathIeeeDoubTrans" for nearly every transcendental).
