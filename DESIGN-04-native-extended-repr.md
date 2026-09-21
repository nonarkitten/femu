# Design: native internal representation (checklist `#4`)

Status: **design + measurement only** — no op files touched. This is the
deliverable for kicking off `#4`; see the recommendation at the end for
what (if anything) a follow-up branch should actually implement.

## The idea, as written in the checklist

> Native internal representation: carry FP values internally in a format
> matching the CPU's 80-bit extended register (explicit integer bit,
> 16-bit exponent) instead of packed IEEE double, so `fmove` to/from an
> FPn register needs no hidden-bit insert/strip; convert to IEEE
> double/single only when writing to memory in that format.

## Current architecture

`RegFpn` (`src/utils/fpu.asm`) is 16 entries × 8 bytes, each holding a
plain IEEE-754 double (`d0`=hi32, `d1`=lo32) with the usual implicit
hidden bit. `MOVEFPNTODN`/`MOVEDNTOFPN`/`MOVEFPNTOEA`/`MOVEEATOFPN`
(`src/utils/macros.asm`) move values between `RegFpn` and working
registers or memory as a **straight copy** — no conversion, because the
stored format already matches what the arithmetic macros expect.

Conversion only happens at `src/utils/type.asm`'s boundary functions,
called when a memory operand's format isn't already a double:
`ByteToDouble`/`WordToDouble`/`LongToDouble` (call the stubbed
`mathieeedoubbas.library`), `SingleToDouble`/`DoubleToSingle` (stubbed
`mathieeedoubtrans.library`), and — the pair `#4` is about —
`ExtendedToDouble`/`DoubleToExtended`, which are **native code**, no
library call, doing real bit-shuffling: rebias an 15-bit exponent to
11-bit (or back), and insert/strip the hidden bit while resizing a
63/64-bit mantissa to/from a 52-bit fraction.

`fmovem` (`src/ops/fmovem.asm`) calls `ExtendedToDouble`/
`DoubleToExtended` **once per register** in the register list
(`FMOVEMEAFPN`/`FMOVEMFPNEA`), so an 8-register `fmovem.x fp0-fp7,(ea)`
pays this conversion cost eight times over.

Register-to-register `fmove fpN,fpM` never touches this code path at
all — `GETEAVALUE`'s register-direct case already just copies the
double bits, since that's the internal format. **This matters**: the
checklist item's stated motivation ("`fmove` to/from an FPn register
needs no hidden-bit insert/strip") already holds for the
register-to-register case today. The actual cost `#4` can remove only
exists at the **`.x`-format memory boundary** (`fmove.x`, `fmovem.x`,
`fsave`/`frestore` state frames) — the design and the measurements below
are scoped to that, not to register moves in general.

## Measured baseline (`bench/`)

Added `bench/src/fmove_probe.asm` + a probe in `bench/src/harness.c`
(`run_fmove_probe`) that exercises the six paths `#4` would change,
using `(a0)` addressing into a scratch memory buffer. Run with
`make run` in `bench/` — output is the `fmove/fmovem memory-operand
probe` section. Current numbers (femu.020, `CPU020`):

| op | cycles | correct? |
|---|---|---|
| `fmove.x (a0),fp0` (extended → internal) | 844 | **no** — see bug below |
| `fmove.x fp0,(a0)` (internal → extended) | 732 | yes |
| `fmove.d (a0),fp0` (double → internal) | 695 | yes |
| `fmove.d fp0,(a0)` (internal → double) | 605 | yes |
| `fmovem.x (a0),fp0-fp3` (4 regs, extended → internal) | 1457 | no (same bug) |
| `fmovem.x fp0-fp3,(a0)` (4 regs, internal → extended) | 1369 | yes |

**The key finding**: `fmove.d` is *already cheaper than* `fmove.x`
today, by ~130-240 cycles, precisely *because* the internal format is
double. Flipping the internal format to extended does not eliminate a
cost — it **relocates** it: `fmove.x` would become the ~600-cycle case
and `fmove.d` would become the ~700-850-cycle case. For a single
`fmove`, this is close to a wash, not a win, unless real Amiga FP code
is demonstrably `.x`-heavy rather than `.d`-heavy (see "Open question"
below — this is exactly the kind of thing that would have been guessed
wrong without measuring first, per `CLAUDE.md`).

**Where there's a real, non-wash win**: `fmovem`. The per-register
conversion cost is paid once per register in the list, so it scales
linearly — a full `fmovem.x fp0-fp7,(ea)` (8 registers, common in
task-context save/restore) would pay roughly double the 4-register
number above, i.e. on the order of **2700-2900 cycles just in
conversion overhead**, all of which a native-extended internal format
(or even just a batched, non-per-register conversion routine) would
remove. This is the part of `#4` with an unambiguous payoff.

## A bug this probe found (not introduced by it)

`fmove.x (a0),fp0` and `fmovem.x (a0),...` both come back with a tiny
but real error: converting extended `1.5` round-trips as
`1.5000000001164082`, not `1.5`. `fmove.x fp0,(a0)` (the other
direction) and everything else is exact. This is a pre-existing bug in
`ExtendedToDouble`'s mantissa bit-shuffling (`src/utils/type.asm`),
unrelated to `#4` and not introduced by this probe — a hand simulation
of the macro's `bfins`/shift sequence in Python gives the *correct*
bit pattern, so the discrepancy is either in an interaction this
simulation didn't capture or in a step not yet identified; root-causing
it further is out of scope for a design-only pass. Worth a small,
independent bugfix branch regardless of `#4`'s fate (same category as
the small fixes already landed this session) — logged in `ISSUES.md`.

## Proposed format (for if/when this is implemented)

Match the real Motorola memory "extended" layout exactly — this is the
same shape `ExtendedToDouble`/`DoubleToExtended` already read and write
via `movem.l d0/d1/d2,(ea)`, so `RegFpn` becomes a drop-in match for it:

```
word0 (16 bits): sign(1) | exponent(15, bias 16383)
word1 (16 bits): reserved, always 0
word2 (32 bits): mantissa bits 63-32 (bit 63 = explicit integer bit)
word3 (32 bits): mantissa bits 31-0
```

12 bytes/register (up from 8) → `RegFpn` grows from 128 to 192 bytes.
`MOVEFPNTODN`/`MOVEDNTOFPN`/`MOVEFPNTOEA`/`MOVEEATOFPN` become 3-register
(`d0/d1/d2`) `movem.l`s scaled by `*12` instead of `*8` — mechanical.

## Everything that would need to change (full-scope estimate)

This is **not** a `fadd`/`fmul`-sized change. Every file that reads or
writes an internal register's raw bits needs updating to the new
16-bit-exponent, explicit-bit, 64-bit-mantissa layout:

- **`src/utils/macros.asm`**: the four move macros above (mechanical).
- **`src/utils/type.asm`**: `ExtendedToDouble`/`DoubleToExtended`
  effectively invert roles — the extended↔internal direction becomes a
  straight copy (delete the conversion), and what's newly needed is
  `DoubleToInternal`/`InternalToDouble` doing the *same kind* of
  rebias-and-resize work these already do, just triggered by `.d`
  instead of `.x`. `Byte/Word/Long/SingleToDouble` and reverse all need
  an "Internal" variant too (double is no longer free).
- **`src/ops/fadd.asm`, `fmul.asm`, `fdiv.asm`**: `FE_FADD`/`FE_FMUL`/
  `FE_FDIV` are built around an 11-bit exponent field and hidden-bit-at-
  bit-20 convention throughout (exponent extraction/compare/bias-1023,
  `NORMALIZE`'s target bit position, `MUL64`/`DIV64`'s 53-bit mantissa
  assumption). All of it re-derives for a 15-bit exponent (bias 16383)
  and a mantissa that's *already* explicit-bit (no more `bset #20` —
  genuinely simpler there) but 64 bits wide instead of 53 (wider
  `MUL64`/`DIV64` inputs, different rounding bit-width arithmetic).
- **`src/utils/double.asm`** (`NORMALIZE`, `ALIGNEXPONENT`): same
  11-bit/bit-20 assumptions, need the 15-bit/bit-63 equivalents.
- **`src/ops/fcmp.asm`**: `ISNAN`/`FAKE64` (`src/utils/math64.asm`)
  hardcode IEEE-double NaN/Inf bit patterns (`$7FEFFFFF`/`$FFF00000`) —
  need 15-bit-exponent equivalents.
- **`src/utils/macros.asm`**'s `SETCC`: same — its zero/NaN/Inf checks
  are double-shaped.
- **`src/ops/fscale.asm`, `fgetexp.asm`, `fgetman.asm`**: all do
  `bfextu d0{1:11}` / `bfins ...{1:11}` directly against the 11-bit
  exponent field and the `-1023` bias — every one needs the 15-bit/
  16383 equivalent. (`fgetman.asm` is already flagged broken in
  `ISSUES.md` — worth fixing *as* part of this rewrite, not before.)
- **`src/ops/fneg.asm`, `fabs.asm`**: only touch bit 31 (the sign bit),
  which stays in the same place in the proposed layout — no logic
  change, just wider data now flowing through `GETEAVALUE`/
  `MOVEDNTOFPN`.
- **`src/ops/fmovecr.asm`**: the `CCC` constant ROM (`src/utils/fpu.asm`)
  is pre-baked as IEEE doubles. Either add a conversion step here
  (this op is cold — rarely executed — so the cost doesn't matter) or
  re-encode the whole table as extended constants (zero runtime cost,
  more upfront data-entry work, and `fpu.asm`'s table is already mostly
  zeros/unfinished per `ISSUES.md`).
- **`src/ops/fmovem.asm`**: `FMOVEMEAFPN`/`FMOVEMFPNEA` lose their
  `jsr ExtendedToDouble`/`DoubleToExtended` entirely for the `.x` case
  — this is where the real win shows up. Non-`.x` formats need the new
  `*ToInternal`/`InternalTo*` calls instead.
- **The `FPN080` path** (Apollo 68080 hardware extended registers,
  `ifd FPN080` branches throughout the same macros) is untouched by
  construction — it already operates on real hardware extended
  registers via `storei`/`loadi`/`vperm`, independent of whatever
  software format the non-`FPN080` path uses.

Rough size: touches 11+ op files plus 3 utility files, versus `#1`'s 2
op files + 1 utility file. Every arithmetic op's correctness needs
re-verifying against `bench/`'s host-double reference after the
exponent/mantissa width change — non-trivial re-validation, not just
new code.

## Open question this data raises (needs a human call, not a guess)

The measured "wash" for single `fmove.x` vs `fmove.d` means the whole
premise of `#4` — that extended-shaped internal storage is a net win —
depends on **which memory format real Amiga FP code actually uses
more**. Two considerations pull in different directions:

- Amiga C compilers (SAS/C and others) map C's `double` to `fmove.d`
  for parameter passing and variable storage when targeting the 68881 —
  so *generated* code from C sources likely leans `.d`-heavy for
  ordinary arithmetic, where the register-to-register case (already
  free either way) dominates anyway.
- `fmove.x`/`fmovem.x` are what task-context save/restore and
  highest-precision hand-written assembly use — `fsave`/`frestore`
  sequences, and `fmovem.x fp0-fp7` specifically, which is exactly
  where this data shows a real, non-wash win (the per-register
  multiplier).

This isn't resolvable by more local measurement — it needs either
real profiling of representative Amiga FP-heavy software, or a
judgment call on which use case femu should be optimized for.

## Recommendation

Don't take the full-scope rewrite as specified. Two narrower paths that
the data actually supports, either of which is a much smaller and
safer branch than the full representation swap:

1. **Target `fmovem` specifically**, not the whole internal format.
   Batch the conversion (convert the whole register range's worth of
   data in one pass instead of `jsr`ing `ExtendedToDouble`/
   `DoubleToExtended` once per register) or unroll it to cut per-call
   overhead. Keeps `RegFpn` as double, touches `fmovem.asm` and maybe
   `type.asm`, none of the arithmetic ops. Directly addresses the one
   case this session's data shows a clear, non-wash win, without the
   `#1`-sized-times-five risk of the full rewrite.
2. **If the full rewrite is still wanted** (e.g. because task-switch-
   heavy, `.x`-heavy software is what actually matters for this
   project's goals), do it as a genuinely separate, large effort — not
   folded into finishing `#4` in one sitting — given the file count
   above. `bench/`'s new probe vectors are ready to validate it either
   way.

Either way: fix the `ExtendedToDouble` rounding bug this probe found,
independently, first — it's small, real, and would otherwise get
carried into or masked by whichever path is chosen next.
