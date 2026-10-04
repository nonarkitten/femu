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
| [8](#row-8) | EA-decode fast path for the common addressing modes | 0 | ✅ Done | `claude/keen-mendel-3hb6vs` |
| [9](#row-9) | Fast paths for cheap transcendental special cases | 1 | ✅ Done (`ftentox` scoped out) | `claude/keen-mendel-3hb6vs` |
| [10](#row-10) | Native transcendentals (drop `mathieeedoubtrans.library`) | 1, 4 | 🔲 In progress (11/14 + `fsqrt` done — see row) | `claude/keen-mendel-3hb6vs` |
| [11](#row-11) | Fix `fmovem` bulk register move | 0 | 🔲 Not started | `perf/11-fmovem-fix` |
| [12](#row-12) | Relaxed-precision internal format: keep the 80-bit layout but force the low 16/32 mantissa bits to 0 (round) or 1 (truncate), and do the arithmetic itself at the resulting 48/32 effective bits | 4 | 🔲 Not started | `perf/12-relaxed-precision` |

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
- **Status:** ✅ Done
- **Branch:** `claude/keen-mendel-3hb6vs`
- **Result:** `GetEaValue` (`src/utils/ea.asm`) is the single place every
  `GETEAVALUE` caller funnels through for a memory operand; it used to
  dispatch on data length only, then each of its 7 format handlers did
  its own `jsr GetEa` (a second, nested subroutine call, complete with
  `GetEa`'s own redundant re-check of the register-to-register bit
  `GetEaValue` had already ruled out). The fast path resolves the
  address **once**, inline, right in `GetEaValue`, for the 5 common
  modes — removing that whole nested call for them — and falls through
  completely unchanged to the existing `jsr GetEa` for everything else
  (indexed, memory-indirect, absolute, PC-relative, immediate, and
  mode 001's unsupported `An` direct). `(An)+`/`-(An)` with register 7
  (`sp`) also fall through to the slow path: `GetEa`'s
  `EaAnIndirectPostincSp`/`PredecSp` need the heavier `STACKSR`/
  `STACKSL` stack-shift loops for the user-mode case, not worth
  duplicating here for what's already a rare addressing choice for an
  FP operand.

  **A real design mistake, caught by measuring rather than assumed
  correct from the logic alone:** the first version dispatched the 5
  fast modes with a linear `cmp`/`bcc` chain (check Dn, else check An,
  else check `(An)+`, ...). Measured against the *old* `jsr GetEa`
  path, `(An)+`/`-(An)`/`(d16,An)` came out **slower**, not faster —
  each sits further down the chain than `(An)`, so it paid for every
  earlier mode's comparison on top of its own, outweighing the call it
  saved. Fixed by dispatching on the 3-bit mode field through a small
  jump table instead (mirroring `GetEa`'s own dispatch shape: `bfextu`
  + `jmp`, O(1) to reach any mode), so the *only* thing the fast path
  removes is the call/return pair and the redundant bit-14 recheck — a
  uniform win instead of a chain-position-dependent one. A further
  micro-optimization in `.FastPostinc`/`.FastPredec` (needed to check
  for `sp` before committing to the fast path) replaces a second
  `bfextu` re-extraction of the register field with a cheaper `move.b`
  off the one `bfextu` already done for the `sp` check — small, but
  free once noticed.

  **Measured** (`bench/`'s existing `fmove` memory-operand probe for
  `(An)`, plus a new dedicated EA-fast-path probe — `bench/src/
  ea_fastpath_probe.asm` — for `(An)+`/`-(An)`/`(d16,An)`/`Dn` direct at
  all three of its size-adjusted widths, covering what the existing
  probes didn't; "before" numbers for the new probe's rows were
  captured by temporarily reverting just `ea.asm` and rerunning it,
  since those rows didn't exist in any prior baseline): `fmove.x
  (a0),fp0` 736 → **719** (−17), `fmove.d (a0),fp0` 881 → **864** (−17),
  `fmove.l (a0)+,fp0` 921 → **916** (−5), `fmove.l -(a0),fp0` 923 →
  **918** (−5), `fmove.l (4,a0),fp0` 924 → **907** (−17), `fmove.w
  d0,fp0` 936 → **921** (−15), `fmove.b d0,fp0` 926 → **909** (−17),
  `fmove.l d0,fp0` 932 → **905** (−27). Every fast-pathed mode is a
  real, bit-exact win — none a wash, none a regression — with `(An)+`/
  `-(An)` the smallest (the `sp`-exclusion check's cost eats into their
  savings the most) and Dn-direct long the largest (no extension word,
  no stack-shift check at all). All existing register-direct vectors
  and every other probe remain bit-exact (`MATCH`/`ok`) on both
  `femu.020` and `femu.020m` — this only touches `GetEaValue`'s own
  code and `GETEA`'s other 6 callers (`fmove`/`fmovem`/`fsave`/
  `frestore`/`fmovefpcr`/`fscc`) are untouched, since they call `GetEa`
  directly and never went through `GetEaValue` at all.

<a id="row-9"></a>
#### #9 — Transcendental fast paths for cheap special cases

- **Idea:** Fast paths for cheap special cases: `ftwotox`/`ftentox` with
  an integer exponent (bump the exponent field, no `Pow()` call),
  `fetox`/`flogn` at 0/1, multiply/divide by 0/1/power-of-two, `fsqrt` at
  0/1.
- **Depends on:** 1
- **Status:** ✅ Done (`ftentox` scoped out)
- **Branch:** `claude/keen-mendel-3hb6vs`
- **Result:** Every fast path here skips the slow library `jsr`
  (`fetox`/`flogn`/`fsqrt`/`ftwotox`) or the heavy native loop
  (`fmul`/`fdiv`'s `MUL64`/`DIV64`) entirely for its special case,
  landing on a result built from a handful of register ops instead —
  not a cheaper call, no call at all.

  **`ftwotox` with an integer operand:** for `2^x` with `x` an exact
  integer small enough that `16383+x` still fits the result's 15-bit
  exponent field, the result is exactly sign=0, exponent=`16383+x`,
  mantissa=explicit-bit-only — no `InternalToDouble`, no library `Pow`
  call. Checked, not assumed: verified against an independent exact-
  `Fraction` reference in Python (0/200000 random cases + boundary
  cases up to `+-32767`) before writing the `src/ops/ftwotox.asm`
  assembly. Falls through unchanged to the existing slow path for
  anything not a small integer — including `|x|<1` (only `x=0` could
  ever qualify, and 0 isn't reached this way) and anything whose
  exponent-bump would itself overflow the 15-bit field, both rare and
  already handled (however that turns out) by the untouched slow path.

  **`ftentox` is explicitly NOT given the same treatment** — "bump the
  exponent field" is a base-2 trick (it multiplies by a power of 2);
  it does not generalize to base 10 (`10^x` is not an exponent-field
  operation on a binary float). A correct fast path for `ftentox`'s
  integer case would need something structurally different — binary
  exponentiation using the constant ROM's existing powers-of-ten
  entries (`CCC` in `src/utils/fpu.asm`), chaining several `FE_FMUL`
  calls with sign handling for negative exponents — real, but a
  meaningfully larger and separately-riskier piece of work than
  anything else in this row, not an "easy" fast path. Left as a
  candidate follow-up, not blocking this row.

  **`fetox`/`flogn` at their identity argument:** `fetox(0) = 1.0`
  and `flogn(1) = 0.0` exactly, for either sign of zero on the
  `fetox` side (consistent with the denormal-as-zero convention
  `FE_FADD`/`FE_FMUL`/`FE_FDIV`'s own ladders already use — exponent
  field zero is the complete zero test); `flogn`'s one-check requires
  sign clear (`-1.0` is deliberately excluded: `ln(-1)` is `NaN`, not
  `0`).

  **`fsqrt` at 0/1:** `sqrt(0) = 0` and `sqrt(+1) = +1` are both
  exactly *self-identical* results, so the fast path is a pure
  pass-through — `d0`/`d1`/`d2` aren't even written, just left as
  `GETEAVALUE` produced them. The zero check ignores sign (`sqrt(-0)
  = -0`, still self-identical); the one check requires sign clear
  (`-1.0` excluded: `sqrt(-1)` is `NaN`, not `-1`).

  **`fmul`/`fdiv` by `+-1` or by a clean power of two:** inserted into
  `FE_FMUL`/`FE_FDIV`'s `.MainBody`, right after the sign is computed
  and before the exponent/mantissa work the real multiply/divide
  needs, so it only has to check whether `src`'s mantissa is
  explicit-bit-only (checking `src`, i.e. "multiply/divide BY X", not
  `dst` — multiplication's own commutativity would make a `dst`-side
  check equally valid, but that doubles the checking for a case this
  row's own phrasing doesn't ask for, so it's left out). `src == +-1`
  returns `dst` with its sign replaced by the already-computed XOR'd
  sign, mantissa/exponent untouched — skips everything. `src == +-2^k`
  (`k != 0`) returns `dst`'s mantissa untouched with the exponent
  moved by `k` — skips `MUL64`'s four `mulu.l`s or `DIV64`'s 64+1-
  iteration loop, but still needs the same combined-exponent
  arithmetic the slow path would've done anyway (so the win is purely
  "no multiply/divide", not "no exponent math too"). `multiply/divide
  by 0` needed no new code at all — `FE_FMUL`/`FE_FDIV`'s existing
  special-case ladder (from `#1`/`#3`) already short-circuits a zero
  operand.

  **Measured** (`bench/`, register-direct; new rows added to
  `vectors/ops.txt`/`src/ops.asm` in their established lockstep
  convention, since every case here is register-to-register — no new
  probe infrastructure needed): `fetox(0)` **680** vs `fetox(3.66)`
  (ordinary, slow path) **968** — and the 680 is now a *real* number,
  not a `(stub)` approximation, since the library call is skipped
  entirely. `flogn(1)` **696** vs `flogn(7.25)` **966**. `fsqrt(0)`
  **668**, `fsqrt(1)` **686**, vs `fsqrt(4.25)` **980**. `ftwotox(3)`
  and `ftwotox(-2)` both **784** vs `ftwotox(12.5)` (non-integer, slow
  path) **1030**. `fmul(-3.5, 2.0)` (power-of-two, already in the
  existing vector set) **1200 → 862** (−338); `fmul(5.5, 1.0)`
  (exactly-one, new vector) **836** (the slightly bigger win over
  power-of-two makes sense — no exponent recombine needed either).
  `fdiv(-4.0, 2.0)` and `fdiv(100.0, 4.0)` (power-of-two, already in
  the existing vector set) **5744 → 862** (−4882 — `fdiv`'s fast path
  is the single biggest win in this row, unsurprising given `DIV64`'s
  cost); `fdiv(5.5, 1.0)` (exactly-one, new vector) **836**.
  `fdiv(100.0, 0.5)` (power-of-two with a *negative* exponent
  difference, new vector) **862**, confirming the exponent-move
  direction is right for that case too. Every ordinary (non-special)
  `fmul`/`fdiv`/`fetox`/`flogn`/`fsqrt` vector pays a small, flat,
  unavoidable tax for the new checks when they don't match — `fmul`/
  `fdiv` +12, `fetox`/`flogn` +12-14, `fsqrt` +26 (two separate
  checks), `ftwotox` +64 on a non-integer operand (the most checks of
  any case here, since it has to rule out both "too large" and "has
  fractional mantissa bits" before giving up) — all measured, not
  estimated, and all bit-exact (`MATCH`) against the host reference,
  including every pre-existing vector.

<a id="row-10"></a>
#### #10 — Native transcendentals

- **Idea:** Implement `facos`/`fasin`/`fatan`/`fcos`/`fcosh`/`fsin`/
  `fsinh`/`ftan`/`ftanh`/`fetox`/`flogn`/`flog2`/`flog10`/`fsincos`
  (and, it turned out, `fsqrt`'s general case too — see below) without
  `mathieeedoubtrans.library`, building on the native representation
  from `#4`. Explicit motivation this time isn't raw speed (the user:
  "I don't expect a huge win in performance") — it's dropping the
  AmigaOS library dependency entirely, so this can in principle run
  on any 68k target (Mac, Atari), not just Amiga.
- **Depends on:** 1, 4
- **Status:** 🔲 In progress. Done: `fsqrt` (found along the way, not
  one of the row's original 14), `fetox`, `flogn`, `ftwotox`,
  `ftentox`, `flog2`, `flog10`, `fsinh`, `fcosh`, `ftanh`, `fsin`,
  `fcos`, `fsincos`, `ftan`, `fatan`. Left: `fasin`/`facos` — both
  derive cheaply from `fatan` (`asin(x)=atan(x/sqrt(1-x^2))`,
  `acos(x)=pi/2-asin(x)`), the last genuinely new algorithm in this
  row having already landed with `fatan` itself.
- **Branch:** `claude/keen-mendel-3hb6vs`
- **Result:** This row is far bigger than any other on the checklist
  (14 functions named, several needing a real numerical algorithm, not
  a bit-trick), so it's landing in pieces rather than one commit — each
  piece fully implemented, verified, and measured on its own, same bar
  as every other row, updated here as it goes rather than held back
  until the whole row is done.

  **Shared infrastructure** (`src/utils/nativemath.asm`): thin `jsr`/
  `rts` wrappers — `NativeFadd`/`NativeFsub`/`NativeFmul`/`NativeFdiv`
  — around the existing `FE_FADD`/`FE_FMUL`/`FE_FDIV` macros, letting
  a transcendental's range-reduction/polynomial code chain several
  arithmetic steps via plain calls instead of inlining each macro's
  full body (`FE_FMUL` alone is well over 100 instructions) at every
  step. This is deliberately the opposite choice from `FE_ADD`/
  `FE_FMUL`/`FE_FDIV` themselves staying inlined macros at their own
  hot call sites — `CLAUDE.md`'s "keep macros flat in hot paths"
  cuts the other way for genuinely cold code chaining many steps,
  which is exactly what every function in this row is.

  **`fsqrt` (general case) — done.** The `#9` fast path for `0`/`+1`
  stays; everything else now goes through `NativeFsqrt`
  (`src/utils/nativemath.asm`): Newton-Raphson on the *reciprocal*
  square root (`y := y*(1.5 - 0.5*m*y^2)`), which avoids `fdiv`
  (expensive — `DIV64`'s 64+1-iteration loop) inside the iteration
  entirely, at the cost of a division-free initial guess instead of a
  division-based one. The operand's mantissa and exponent parity are
  split so the iteration always runs on a value `m` in `[1,4)` with
  *no mantissa bit-shifting* — doubling a normalized mantissa's bit
  pattern directly doesn't fit back in 64 bits (the explicit bit would
  shift out), but doubling its *value* is exactly "same bits, exponent
  one higher," which is all the parity adjustment needs. Two exact,
  trivial constants (`0.75`/`0.5`) serve as the initial guess depending
  on that parity — verified in Python before writing any assembly that
  a `y0=1.0` guess does *not* converge globally (diverges outright
  for `m` near 4), while these two converge to within ~3 ULP of a
  double-precision reference after 6 iterations across 1M+ random
  samples spanning both ranges and their boundaries; 7 iterations are
  used in the real implementation for the wider 64-bit mantissa's
  extra precision headroom. Inf/NaN pass through unchanged (same
  self-identical trick as the `0`/`+1` fast path); a negative finite
  operand constructs a NaN (exponent all-ones, mantissa not the clean
  Infinity pattern) rather than running the iteration on it.

  **Measured** (`bench/`, register-direct, 8 new vectors spanning
  `1.5e-10` to `1.5e10` and both exponent parities): every case
  `MATCH`es the host `sqrt()` bit-exactly, including the pre-existing
  `fsqrt(4.25)` vector, which now shows a real number instead of a
  `(stub)` approximation — `980 (stub)` → **14092–15385** (no longer
  `(stub)`: this is the *actual* now-measurable cost, not a smaller
  number that excluded the real library's work). Slower than the old
  library call's unmeasured stand-in, as expected and explicitly not
  the point of this row — what's gained is running with zero AmigaOS
  dependency for this op, correctly, at a real and now fully known
  cost. All existing vectors and probes remain bit-exact elsewhere
  (only the pre-existing, unrelated `flog2` 1-ULP discrepancy persists).

  **`fetox` — done.** The `#9` fast path for `+0`/`-0` stays; `+Inf`/
  `-Inf`/NaN pass through the same way `fsqrt` does (self-identical
  `+Inf`, `-Inf`→`+0`, NaN discriminated the same way `SETCC` itself
  does); every other finite `x` goes through `NativeFexp`
  (`src/utils/nativemath.asm`): standard range reduction
  `x = k*ln(2) + r` with `k = round(x * 1/ln2)` (`NativeRoundToInt`,
  new) and `|r| <= ln(2)/2`, a 16-term (`1/0!`..`1/15!`) Horner-evaluated
  Taylor polynomial for `e^r`, then `e^x = e^r * 2^k` applied as a plain
  exponent bump rather than a multiply — the same technique `#5`/`#9`
  already use. `k` round-trips through a new `NativeIntToExtended`
  (the inverse of `NativeRoundToInt`) so it can be multiplied against
  `ln(2)` in extended precision. All 16 Taylor coefficients were
  verified in Python (exact `Decimal` arithmetic) to bring the series'
  *own* truncation error below 2^-63 across the whole reduced range
  before any assembly was written.

  Two real, pre-existing bugs surfaced while landing this (not
  checklist-#10-specific — both are now fixed, see their own commits/
  comments):

  - **`d7` is not a free scratch register for native-math loop
    counters.** `src/utils/constants.asm` aliases `INSTRUCTION equr
    d7` — the live decoded opcode word that every handler's
    `GETREGISTER` (and `HandleException`'s own chain-loop decode)
    reads *after* the handler returns. A Horner-loop counter parked in
    `d7` (and `NativeFsqrt`'s pre-existing iteration counter, same
    mistake, merged earlier with this row) silently corrupts the
    destination FPn index the caller decodes next, so the correct
    result gets written into the *wrong* register while the real
    destination keeps its original, unmodified input — "wrong answer"
    looked exactly like "the op didn't run" for these monadic,
    self-overwriting (`fp0,fp0`) test vectors. `NativeFsqrt` only
    "worked" by coincidence: its loop happens to leave `d7` at exactly
    `0`, which decodes to `fp0` regardless. Fixed by moving both loop
    counters into memory (`SqrtIterCount`/`ExpIterCount`) instead of a
    register — see `nativemath.asm`'s header comment for the full
    writeup.
  - **`FE_FADD`'s result sign was silently discarded for any case
    reaching `MainBody`'s `DiffSigns`/`SameSign` paths.** The sign is
    computed there as `d6 = <something> & $80000000` (bit31
    convention), but the final construction used `bfins d6,d0{0:1}`,
    which inserts only `d6`'s **bit 0** — always `0` for a value built
    by masking with `$80000000`. Every add/sub whose true mathematical
    result is negative silently came out positive; never caught
    because no existing vector exercised `FE_FADD`'s `MainBody` with a
    negative result (shared by `fadd` *and* `fsub`, since `fsub` is
    `bchg #31,d3` + `FE_FADD`). Fixed by changing the final step to
    `or.l d6,d0` (matching `FE_FMUL`'s own, correct convention for the
    same job). Caught here because `NativeFexp`'s range reduction
    needs `r = x - k*ln(2)` to come out negative for roughly half of
    all inputs (positive `x` with `k` rounding up past it) — the very
    case nothing had tested before.
  - (Non-correctness, bench-only.) The harness's own `ops[]`/`vecs[]`
    buffers were hardcoded to 64 entries with no overflow check —
    `fread`'s byte count and `load_vectors`'s row count both silently
    capped there, so adding vectors past #64 made the lockstep count
    check compare two equally-truncated numbers and report nothing
    wrong while 5 new vectors silently never ran. Bumped to 128 with a
    comment explaining why, in `bench/src/harness.c`.

  **Measured** (`bench/`, register-direct, 6 new vectors: negative
  `x`, a larger-magnitude positive and negative `x`, a small nonzero
  `x`, `+Inf`, `-Inf`): every case `MATCH`es the host `exp()`
  bit-exactly, including the pre-existing `fetox(3.66)` vector, which
  now shows a real number instead of a `(stub)` approximation — no
  longer `(stub)`, this is the actual now-measurable cost. Slower than
  the old library call's unmeasured stand-in, as expected and
  explicitly not the point of this row. Two new vectors (`fsub 2.0
  5.0`, `fsub -2.0 -5.0`) and one (`fadd 2.0 5.0`) were added
  specifically to catch and pin the `FE_FADD` sign bug above; all
  existing vectors and probes remain bit-exact elsewhere (only the
  pre-existing, unrelated `flog2` 1-ULP discrepancy persists).

  **`flogn` — done.** The `#9` fast path for `+1.0` stays; everything
  else goes through `NativeFlogn` (`src/utils/nativemath.asm`): read
  `x = m * 2^e` directly off the operand's own exponent/mantissa split
  (`m` in `[1,2)`, free — no bit-shifting needed, same as the rest of
  this row), then `ln(x) = ln(m) + e*ln(2)` (`e*ln(2)` reuses
  `NativeFexp`'s own `ExpLn2` constant rather than a second copy).
  `ln(m)` itself uses the atanh series `s = (m-1)/(m+1)`,
  `ln(m) = 2*atanh(s) = 2*s*(1 + s^2/3 + s^4/5 + ...)` — but `m` alone
  gives `s` up to `1/3`, needing an impractically long series (~20
  terms for `2^-63`, verified in Python), so `m` is first centered
  against `sqrt(2)`: if `m >= sqrt(2)`, `m := m/sqrt(2)` and `ln(2)/2`
  is added back once `ln(m/sqrt(2))` is known; otherwise `m` is already
  in `[1,sqrt(2))` and the correction is `0`. This halves `s`'s worst
  case to `(sqrt(2)-1)/(sqrt(2)+1) ~= 0.1716`, and since `m` and
  `sqrt(2)` share the same exponent (`16383`) by construction, "`m >=
  sqrt(2)`" is just an unsigned 64-bit mantissa compare — no general
  float comparison needed. 13 terms were verified in Python (exact
  `Decimal` arithmetic, 300000+ random samples plus the `m=1`/`m->
  sqrt(2)` boundary cases) to bring the series' own truncation error to
  ~0.0015 ULP, the same comfortable margin `fetox`'s 16-term series
  uses. Special cases: `0` (either sign) → `-Inf` (a pole error, same
  as every host libm checked against); `+Inf` passes through unchanged;
  `-Inf` and any finite negative `x` construct a NaN (`ln` of a
  negative isn't real); an actual NaN passes through unchanged — all
  discriminated the same way `SETCC`/`fsqrt`/`fetox` already do.

  Landing `flogn`'s NaN-producing special cases surfaced a real bench
  harness gap: every `MATCH`/`DIFFER` check in `bench/src/harness.c`
  used a bare `==`, which is *always* false for a NaN result (IEEE:
  `NaN != NaN`, even itself) — so a correct NaN answer would have
  printed `DIFFER` regardless. Fixed with a `values_match()` helper
  (`isnan(want) ? isnan(got) : got == want`) used at all 5 comparison
  sites in the file, not just this row's new vectors — the same bug
  would have hit any future op's NaN-producing test the same way.

  **Measured** (`bench/`, register-direct, 9 new vectors: `0.5`/
  `0.0001` exercising a negative `e`, `1.3` exercising no sqrt(2)
  centering, `1.5` exercising it, `1000000.0` exercising a larger
  positive `e`, `0.0`/`-5.0`/`+Inf`/`-Inf` exercising every special
  case): every case `MATCH`es the host `log()` bit-exactly (NaN cases
  included, thanks to the harness fix above), including the
  pre-existing `flogn(7.25)` vector, which now shows a real measured
  cost instead of a `(stub)` approximation. Slower than the old library
  call, as expected and explicitly not the point of this row. All
  existing vectors and probes remain bit-exact elsewhere (only the
  pre-existing, unrelated `flog2` 1-ULP discrepancy persists -- fixed
  for real two rows down, see below).

  **`ftwotox`/`ftentox`'s general case, `flog2`/`flog10` — done.**
  With `fetox`/`flogn` both native, these four were cheap derivations
  rather than needing their own algorithm: `ftwotox`'s general case
  (the `#9` integer-exponent fast path stays for its own cases, but
  doesn't catch `x=0` -- that now falls through to the general path
  below, which still gives the right answer since `e^(0*ln(2))=e^0=1`)
  and `ftentox` (no integer fast path at all, unlike `ftwotox` --
  `#9`'s row already scoped that out, "bump the exponent" being a
  base-2-only trick) both compute `b^x = e^(x*ln(b))`: multiply by the
  shared `ExpLn2`/new `ExpLn10` constant (`src/utils/nativemath.asm`)
  then `jsr NativeFexp`. `flog2`/`flog10` compute `log_b(x) =
  ln(x)/ln(b)`: `jsr NativeFlogn` then multiply by the shared
  `ExpInvLn2`/new `ExpInvLn10` constant. Each op's Inf/NaN (and, for
  the two logs, zero/negative) special cases are discriminated directly
  on the input, duplicated per op rather than shared (matching this
  codebase's existing per-op-ladder style, e.g. `FE_FMUL_SINGLE`'s own
  header comment) -- `ftwotox`/`ftentox`: `+Inf`→`+Inf`, `-Inf`→`+0`,
  NaN passthrough; `flog2`/`flog10`: zero→`-Inf`, `+Inf`→`+Inf`, `-Inf`
  and any finite negative→NaN, NaN passthrough (identical to `flogn`'s
  own ladder, since they share its domain).

  A genuine, unplanned bonus: `flog2`'s long-standing 1-ULP discrepancy
  against the host reference (present since `#9`'s PR, caused by the
  old `log10(x)/log10(2)` library-stub composition rounding differently
  than glibc's direct `log2()`) is simply **gone** now that `flog2`
  computes `ln(x)*(1/ln(2))` instead — not something this row set out
  to fix, just a side effect of the composition changing.

  **Measured** (`bench/`, register-direct, 17 new vectors across the
  four ops: `x=0` for both exponentials, a negative and a large
  non-integer exponent for `ftwotox`, a negative exponent for
  `ftentox`, `+Inf`/`-Inf` for all four, and `0`/negative for both
  logs): every case `MATCH`es the host `pow()`/`log2()`/`log10()`
  bit-exactly, NaN cases included. All four ops' pre-existing vectors
  also now show real measured costs instead of `(stub)` approximations.
  Slower than the old library calls, as expected and explicitly not the
  point of this row. Every other vector and probe remains bit-exact,
  including — for the first time since `#9` — `flog2`'s own prior
  vector, with no `flog2`/`flog10`/`ftwotox`/`ftentox` discrepancy left
  anywhere in the suite.

  **`fsinh`/`fcosh`/`ftanh` — done.** All three derive directly from
  `fetox`'s `NativeFexp`, computing both `e^x` and `e^-x` and
  combining: `sinh(x)=(e^x-e^-x)/2`, `cosh(x)=(e^x+e^-x)/2`,
  `tanh(x)=(e^x-e^-x)/(e^x+e^-x)` (the `/2` implicit in sinh/cosh's own
  definitions cancels in `tanh`'s ratio, so it's never computed there
  at all). The `/2` in `fsinh`/`fcosh` is a plain exponent decrement
  (the inverse of the exponent-bump technique this row already uses
  elsewhere), not a multiply -- but unlike every *other* final bump in
  this row, `fsinh`'s result isn't guaranteed positive (sinh is odd),
  so its sign has to be extracted and reinserted around the decrement
  (`bfextu`/`bfins`, the bit0-right-justified convention those two
  instructions actually agree on -- see `fadd.asm`'s own `MainBody`
  for the same pairing, and `nativemath.asm`'s header comment for why
  the *other* convention, "sign `& $80000000`", does **not** pair
  safely with `bfins`; that mismatch is the exact bug `fadd`/`fsub`
  shipped with until `#10` part 2 caught it). `fcosh`'s own `/2` skips
  that, since both `e^x` and `e^-x` are always positive.

  Each op's special cases reflect its own symmetry rather than copying
  fetox's ladder verbatim: `fsinh` (odd) has zero *and* Inf
  self-identical for either sign, and even collapses Inf/NaN into one
  check (a NaN is self-identical here too, same bits back out being
  correct for a NaN regardless of which function it passed through);
  `fcosh` (even) constructs `1.0` at zero and forces `+Inf` regardless
  of the input's sign; `ftanh` (odd, bounded) is self-identical at
  zero but constructs `+-1` at `+-Inf` (sign kept, magnitude replaced).
  An actual NaN passes through unchanged in all three.

  **Measured** (`bench/`, register-direct, 12 new vectors: a negative
  operand and all of zero/`+Inf`/`-Inf` for each of the three ops):
  every case `MATCH`es the host `sinh()`/`cosh()`/`tanh()` bit-exactly.
  The one pre-existing vector that doesn't, `fcosh(9.43)`
  (`6228.263405943806` vs the host's `6228.2634059438069`), is a real
  1-ULP difference but not a bug on this side: computed against an
  80-digit exact `Decimal` reference, the true value is
  `6228.26340594380641271...`, which our result is *closer* to
  (`4.13e-13` away) than the host's own `cosh()` is (`5.87e-13` away)
  -- the host libm itself has the 1-ULP error here, not femu. Every
  other vector and probe in the suite remains bit-exact.

  **`fsin`/`fcos` — done.** The first of the two pieces in this row
  that needed a real new algorithm rather than a derivation. Standard
  quadrant range reduction (`x = n*(pi/2) + r`, `n = round(x*2/pi)`,
  `|r| <= pi/4`) then separate 11-term Horner-evaluated Maclaurin
  polynomials for `sin(r)`/`cos(r)`, then the usual sin/cos-of-sum
  quadrant table (`n&3` -- a power-of-two mask, not a general mod,
  gives the correct 0..3 result even for negative `n`, the same trick
  `NativeFsqrt`'s own parity split uses) turns `(sin(r),cos(r))` back
  into `(sin(x),cos(x))`. One shared `NativeFsincos` routine
  (`src/utils/nativemath.asm`) computes both at once -- `fsin.asm`/
  `fcos.asm` (and the future `fsincos.asm`) all need the exact same
  reduction, and a second caller needing it was never speculative,
  it showed up immediately. Both series' 11 terms were verified in
  Python (exact `Decimal` arithmetic against an independently-derived
  high-precision pi, 50000+ random `|r|<=pi/4` samples) to bring their
  own truncation error to a small fraction of a ULP. The range
  reduction itself uses a single 64-bit-mantissa `pi/2` constant, not
  a multi-word one -- verified in Python to stay double-accurate for
  `|x|` up to a few thousand (same character as any "plain" sin/cos
  without Payne-Hanek-style huge-argument reduction); nothing in this
  codebase's test range comes close to that, and arbitrary-magnitude
  accuracy is out of scope for a row about portability, not precision
  records.

  Found (and fixed) a real bug in its own constant-generation script
  before it ever reached a test: the Python script that derived the
  Maclaurin coefficients' extended-hex constants forgot the
  alternating `+,-,+,-,...` sign a Taylor series for `sin`/`cos`
  needs (unlike every other series in this row -- `e^x`'s and
  `atanh`'s both have all-positive coefficients, so this specific
  mistake had nothing to copy from). Every coefficient came out a
  clean positive magnitude instead, and the resulting `sin`/`cos`
  were simply wrong for any non-trivial reduced angle. Caught by
  hand-deriving the expected polynomial value in Python at each
  partial Horner step and comparing against a register-level trace of
  the assembly -- the values agreed exactly through the *first*
  Horner term (`CosC10*t+CosC9`) and only diverged once a `C9`-class
  (odd-index, should-be-negative) coefficient's wrong sign accumulated
  through more terms, which is what pointed at the constants
  themselves rather than the loop logic. Fixed by regenerating all 22
  `SinC*`/`CosC*` constants with the sign restored.

  Zero (self-identical for `fsin`, constructed as `1.0` for `fcos`,
  matching `fsinh`/`fcosh`'s own odd/even distinction) and Inf (NaN
  for both -- unlike every *other* Inf case in this row, `sin`/`cos`
  of infinity is genuinely undefined, the function keeps oscillating
  forever rather than approaching any limit) are discriminated the
  same way the rest of `#10` already does; an actual NaN passes
  through unchanged.

  **Measured** (`bench/`, register-direct, 16 new vectors: all four
  quadrants via both a positive and negative operand, a larger-
  magnitude operand needing several periods of reduction, zero, and
  `+Inf`/`-Inf` for both ops): every case `MATCH`es the host `sin()`/
  `cos()` bit-exactly, NaN cases included. Every other vector and
  probe in the suite remains bit-exact (only the already-explained
  `fcosh(9.43)` case persists).

  **`ftan`/`fsincos` — done.** Both cheap derivations now that `fsin`/
  `fcos` are native, no new algorithm needed. `ftan(x) = sin(x)/
  cos(x)` — `NativeFsincos` conveniently already returns `sin(x)` in
  `d0:d1:d2` and `cos(x)` in `d3:d4:d5`, the exact dst/src layout
  `NativeFdiv` expects, so no scratch memory at all. `fsincos` calls
  `NativeFsincos` once and writes both results back, instead of this
  row's other ops' single write — the real 68881 `FSINCOS` opcode has
  a second destination-register field ("FPc", for cosine) alongside
  the normal one ("FPs", for sine), which `fsincos.asm` already
  decoded correctly (inherited unchanged from the old library-based
  version); only the special-case ladder (now producing both `sin`
  and `cos` from one branch instead of `fsin.asm`/`fcos.asm`'s two
  separate ones) and the `NativeFsincos` call itself are new. One
  genuine assembly mistake caught immediately by `vasm` itself,
  before any run: `fsincos.asm`'s own NaN-passthrough branch used
  `.IsNan` as a local label name, which collides with `SETCC`'s own
  internal `.IsNan:` label once both expand under the same enclosing
  `FsincosHandler` global label (vasm: `error 75: label
  <FsincosHandler .IsNan> redefined`) — renamed to `.GotNan`.

  Since `fsincos` writes two destination registers, neither
  `vectors/ops.txt`'s single-result convention nor `ops.asm`'s
  lockstep with it can express it — same reasoning as `fmove_probe.asm`/
  `ea_fastpath_probe.asm`'s own existence, so a small dedicated
  `fsincos_probe.asm` + `run_fsincos_probe` (`bench/src/harness.c`)
  were added instead, confirming `fp2:fp1` syntax really does put
  cos in `fp2` and sin in `fp1` (checked against `GETREGISTER`'s own
  two bitfield offsets rather than assumed from the mnemonic) and
  that both land correctly for the same `0.75` operand `fsin`/`fcos`'s
  own vectors already cover.

  **Measured**: `ftan(3.91)` (the one pre-existing vector) now shows
  a real measured cost instead of a `(stub)` approximation, bit-exact
  against the host `tan()`. The new `fsincos` probe reports `ok`
  (both registers match). Every other vector and probe in the suite
  remains bit-exact (only the already-explained `fcosh(9.43)` case
  persists).

  **`fatan` — done.** The one function in this row needing a
  genuinely new algorithm rather than a derivation from `fexp`/`flogn`/
  `fsincos` — `atan`'s own Gregory series (`x - x^3/3 + x^5/5 - ...`)
  converges far too slowly to use directly (its terms decay
  geometrically, by roughly `x^2` each step, not by a factorial like
  `sin`/`cos`/`e^x`'s series do), so two range-reduction identities are
  chained first, both in `NativeFatan` (`src/utils/nativemath.asm`):
  `atan` is odd, so only `|x|` is worked with (sign reapplied at the
  end); `|x|>1` reduces via `atan(x)=pi/2-atan(1/x)`; then
  `|x|>tan(pi/8)` (`=sqrt(2)-1`) reduces further via
  `atan(x)=pi/4+atan((x-1)/(x+1))`, leaving a final range of
  `|x|<=tan(pi/8)~=0.4142` for the series itself. Both reduction tests
  are a plain 3-word unsigned lexicographic compare — valid because
  both operands are positive, finite, normalized extended values, so
  bit-pattern order equals numeric order exactly like IEEE single/
  double (same reasoning `flogn`'s own `sqrt(2)`-centering compare
  relies on, just not restricted to equal exponents here). `pi/2`
  reuses `NativeFsincos`'s own `SinCosHalfPi` rather than a second
  copy (same move as `flogn` reusing `fexp`'s `ExpLn2`); `pi/4` is one
  new constant, verified in Python to be `SinCosHalfPi`'s exact
  mantissa with the exponent field one lower (an exact halving).

  25 Horner terms (`AtanC0`-`AtanC24`) were verified in Python (exact
  `Decimal` arithmetic, 2000+ samples spanning the whole reduced range
  up to and including the `x=tan(pi/8)` edge) to bring the series' own
  truncation error below `2^-64` there — a real margin over the 23
  terms Python found were the bare minimum, and a longer table than
  `fexp`/`flogn`/`fsincos` needed (16/13/11 terms respectively) purely
  because the Gregory series has no factorial in its denominator, just
  `2k+1` — it decays only geometrically (~0.17 per term at the reduced
  range's edge), a real cost of this identity rather than a mistake.

  `atan(0)=0` is self-identical (odd function, zero either sign).
  Unlike every *other* Inf case in this row, `atan` is NOT undefined
  at infinity — it has genuine horizontal asymptotes at `+-pi/2`, so
  `+-Inf` constructs a sign-kept `+-pi/2` instead of NaN; an actual NaN
  passes through unchanged. No bugs hit while implementing this one —
  the range-reduction identities and term count were nailed down in
  Python before any assembly was written, same discipline as the rest
  of this row.

  **Measured** (`bench/`, register-direct, 8 new vectors: a
  no-reduction case, a half-angle-only case, and a reciprocal-only
  case, each with a positive and negative operand, plus zero and
  `+Inf`/`-Inf`): every case `MATCH`es the host `atan()` bit-exactly,
  including the pre-existing `fatan(2.25)` vector. Every other vector
  and probe in the suite remains bit-exact (only the already-explained
  `fcosh(9.43)` case persists).

  **Still to do in this row:** `fasin`/`facos`, both cheap derivations
  from `fatan` + `fsqrt` (`asin(x)=atan(x/sqrt(1-x^2))`,
  `acos(x)=pi/2-asin(x)`) — no new algorithm needed, same shape as
  `ftan`/`fsincos` falling out of `fsin`/`fcos`.

<a id="row-11"></a>
#### #11 — Fix `fmovem` bulk register move

- **Idea:** Fix `fmovem` bulk register move (flagged buggy in a TODO;
  hardware `fmovem` "fixes problems" per the same note) — correctness fix
  that's also a hot path for context-heavy code.
- **Depends on:** 0
- **Status:** 🔲 Not started
- **Branch:** `perf/11-fmovem-fix`
- **Result:** —

<a id="row-12"></a>
#### #12 — Relaxed-precision internal format

- **Idea:** Keep the 80-bit (`RegFpn`) layout from `#4` — same byte shape,
  same `fmove.x`/`fmovem.x` straight-copy win — but force the low 16 or
  32 mantissa bits to a fixed pattern (0 on round, 1 on truncate) and do
  the arithmetic itself at the resulting effective width (48 or 32
  significant bits) instead of the full 64, across every op, not just
  the opcode-forced-single case `#5` already covers. The bet: narrower
  mantissas mean narrower `MUL64`/`DIV64` work (and `ALIGNEXPONENT`/
  `NORMALIZE`) for *all* arithmetic, not only when FPCR or the opcode
  says single — closer to what `#4`'s own design doc originally hoped
  `#4` itself would deliver before measurement showed otherwise.
- **Depends on:** 4
- **Status:** 🔲 Not started
- **Branch:** `perf/12-relaxed-precision`
- **Result:** — Suggested by the user after `#5`/`#8`/`#9` landed; not
  started. Worth noting up front for whoever picks this up: this is a
  real, opt-in *relaxation* in the `CLAUDE.md` sense (the same tradeoff
  `#5` already accepted for the single-precision fast path specifically)
  — it must still fall through to a correct path when precision actually
  matters, never silently round wrong, and the checklist row should
  record where the line is drawn (e.g. does 48-bit mode replace `#4`'s
  64-bit default outright, or sit alongside it as a third FPCR-style
  mode next to extended/single/double?).

See `ISSUES.md` for the original author's per-opcode issue notes — several
rows above trace directly back to entries there (e.g. "calls
MathIeeeDoubTrans" for nearly every transcendental).
