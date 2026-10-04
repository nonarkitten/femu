# Start here

femu is a 68K-assembly software FPU emulator for Amiga. We're working
through a checklist of performance ideas, one branch at a time, each one
measured. Read `CLAUDE.md` for how we work, `README.md`'s "Performance
Optimization Plan" section for the checklist, `BENCHMARK.md` for how to
measure. Don't re-derive any of that here — this file just says what's
next.

## Do this

1. `git checkout master && git pull`
2. Open `README.md`, find the checklist. Pick the lowest-numbered row that
   is still 🔲 *Not started* and whose `Depends on` column is already ✅.
3. `git checkout -b perf/<id>-<slug>`
4. Implement that one idea. Nothing else.
5. Build and run `bench/` (see `BENCHMARK.md`) before *and* after, same
   golden vectors, same CPU target(s) the idea claims to help.
6. Update the checklist row: ✅ + measured delta and merge, or ❌ +
   ~~strike~~ + one-sentence reason and leave the branch pushed. Never
   delete a branch.
7. Back to step 1.

## Current state

`#0`-`#4` are all ✅. `#4` ended up as the full internal-representation
rewrite after all (the design pass's own recommendation was the
narrower `fmovem`-only follow-up, but the user explicitly chose the
bigger scope once shown the tradeoffs, for genuine ~80-bit precision
rather than just perf). `RegFpn` is now 16×12 bytes, byte-identical to
the real 68881 extended memory format — see `README.md`'s `#4` row for
the full measured before/after. Short version: `fmovem.x` got the one
clear win it was always going to get (1369-1457 → 953 cycles, no more
per-register conversion `jsr`); `fmove.x` reg↔mem got faster too
(732-844 → 628-714) while `fmove.d` got correspondingly slower
(605-695 → 769-859, the cost relocated, not eliminated); but reg-to-reg
`fadd`/`fsub` got ~5% *slower* (912/910 → 961/953, the old NEG64+ADD64+
ABS64 sign trick needed a spare top bit that a genuine 64-bit mantissa
no longer has) and `fdiv` got notably slower (4413-4677 → 5227-5693,
`DIV64` now runs 64+1 iterations instead of 54 since a 53→64-bit
mantissa needs more quotient bits and has no spare bit left to fold the
round bit in for free). `fmul` is roughly a wash. So: reg-to-reg
arithmetic did not get "significantly faster" — that premise didn't
hold, confirmed by measurement, same conclusion the design pass already
reached before implementation started.

The pre-existing `ExtendedToDouble` rounding bug (extended 1.5 round-
tripping as 1.5000000001164082) is fixed as part of this — it's now
`InternalToDouble` (`src/utils/type.asm`), and along the way needed
*real* round-to-nearest-even added on top of the old truncate-only
behavior, since this conversion is now on every `fmove.d`/transcendental/
etc. path instead of just the rare `.x` case that used to tolerate it.

Two bugs worth knowing about if you touch `fadd.asm`/`math64.asm`
again: (1) `ABS64`'s "negative if bit 31 set" trick for detecting a
2's-complement add's sign does NOT generalize to a full-width 64-bit
mantissa (its top bit is always set, being the explicit integer bit) —
`FE_FADD` now uses direct same-sign/different-sign branching instead,
see the comment in `fadd.asm`. (2) `DIV64`'s restoring-division loop
relied on the old 53-bit mantissa's 11 bits of headroom to safely
double the remainder each iteration without overflow; a full 64-bit
mantissa has none, so the loop now explicitly handles the doubling's
own overflow bit (see the header comment in `math64.asm`) rather than
silently truncating it. Both were found by hand-simulating the
algorithms in Python against golden vectors when `bench/` showed wrong
(not just slow) results — faster to iterate on than round-tripping
through the real assembler each time.

`fdiv`'s extended-precision path is still dominated by a one-bit-at-a-
time division loop (`DIV64`) — deliberately the simple-and-correct
version, not the fast one (see `#1`'s row in `README.md`). The
hardware-`divu.l`-seeded algorithm flagged here as a good future idea
landed as part of `#5` instead, scoped to the single-precision case
(`FE_FDIV_SINGLE`) rather than replacing `DIV64` itself for extended
precision — that's still open if a future row wants it.

`#5` (single-precision fast path) is done, scoped to `fmul`/`fdiv` (see
its `README.md` row for the full writeup and measured numbers): `fsmul`/
`fsglmul`/FPCR-forced-single `fmul` are ~19% faster than extended `fmul`
(1149 → 957-976 cycles); `fsdiv`/`fsgldiv`/FPCR-forced-single `fdiv` are
roughly **5x faster** than extended `fdiv` (5227-5722 → 1000-1019
cycles) — the single biggest win of the checklist so far, and the "a
lot faster" the user expected to offset `#4`'s `fdiv` regression.
`fadd`/`fsub` single-precision paths were explicitly deferred (much
smaller win there — `FE_FADD`/`FE_FSUB` are already O(1), not an
iterative loop, so there's no `MUL64`/`DIV64`-class win to avoid), left
as a candidate future row. Plain `fmul`/`fdiv` (extended, FPCR not
forcing single) pay a flat +29-cycle tax now for the new runtime FPCR-
precision dispatch check — an honest, unavoidable cost of adding the
check to the hot path, not a regression in the underlying math.

One real vasm bug and a narrower vasm quirk were found and worked
around while wiring up `#5`'s dispatch (both fully described in the
`#5` row, worth reading before writing another macro that's invoked
more than once per file with an `ifnb`-gated call inside it): this
build of vasm goes into unbounded memory allocation instead of a clean
error when a macro that defines local labels is called from both
branches of an `ifnb`/`else` inside another macro that itself gets
invoked more than once in a file, and separately when the same
`ifnb`-tested parameter is blank via a leading comma in one call site
and blank via plain omission in another. Neither is `femu`-specific;
both were reproduced in a few lines of standalone test `.asm`.

`#6` (opcode chaining) is done: `HandleException` (`src/utils/fhandler.asm`)
now loops back into `EmulateInstruction` directly when the instruction word
right after the one it just emulated is also F-line, skipping `rte` +
re-trap for it. Real, measured win on back-to-back FPU code — two chained
`fadd`s 1904→1661 cycles (−243), three chained 2853→2345 (−508, ~2× the
pair's saving, since it skips two trap exits) — at a flat +22-cycle tax on
every op that *doesn't* chain (verified: every single existing benchmark
row, extended and single-precision alike, moved by exactly +22 and nothing
else changed). See `README.md`'s `#6` row for the full writeup, including
one interrupt-latency tradeoff worth knowing (a long chain holds interrupts
masked for its whole length, not just one opcode — not gated behind a flag,
same as real 68881 hardware, but a real cost for interrupt-sensitive code).
A real harness bug was found and fixed along the way, worth knowing before
writing another probe: every existing single-opcode bench probe packed its
test opcodes 4 bytes apart with nothing in between, relying on a *real* CPU
re-trap to naturally stop measurement at the right point — harmless before
chaining existed, but once `HandleException` can peek past one opcode into
the next, a densely-packed probe would silently chain into (and mis-time)
its neighbor. Fixed via `SLOT_STRIDE` (`bench/src/harness.c`): opcodes
under test are now placed 8 bytes apart with a zeroed (non-F-line) gap
between them; verified this doesn't change a single existing number.

`#7` (trim the trap prologue/epilogue) is ❌ — investigated, not
implemented, no benchmark run since nothing safe to measure was built. The
full `movem.l d0-d7/a0-sp` save can't be narrowed per-handler:
`ea.asm`'s `GETEAVALUE`/`GetEa`/`ADDAN` reach any of the 15 general
registers by a *runtime*-computed offset into exactly the frame that
`movem` lays down (`OSTACKAN`/`OSTACKDN` fixed at `-32`/`-64` from
`STACKFRAME`, indexed by the actual 68K register number an opcode's EA
extension word names at runtime), so the save can't be narrowed below the
full set without already knowing which register that is. A real, bounded
subset (register-to-register `fadd`/`fsub`/`fmul`/`fdiv`/`fcmp`/`fabs`/
`fneg`/`ftst`/`fscale`/`fgetexp`/`fgetman`, confirmed by grep to never
touch `a0`/`a2`/`a3`/`a6`) exists but doesn't pay for itself once you try
to build it: skipping those 4 registers from the `movem` transfer list
also shrinks the frame, but `OSTACKAN`/`OSTACKDN`'s fixed-offset-by-
register-number addressing means their slots still have to exist for any
later-in-a-chain (`#6`) instruction that does need them, and gap-filling
to preserve those offsets costs about what the skipped `move.l aN,-(sp)`
did. Real per-handler trimming needs the frame's fixed-offset addressing
scheme itself to change — that's `#8`'s territory (a fast EA-decode path
could plausibly use its own smaller, fixed-shape frame), so `#7` is
effectively blocked on `#8` landing first, not just on `0`/`6`. Full
writeup in `README.md`'s `#7` row; the finding is also recorded as a
comment above `PREHANDLEEXCEPTION` in `src/utils/fhandler.asm` so a future
session doesn't redo the audit.

`#8` (EA-decode fast path) is done: `GetEaValue` (`src/utils/ea.asm`)
resolves `Dn`/`(An)`/`(An)+`/`-(An)`/`(d16,An)` addresses inline, once,
instead of each of its 7 data-length format handlers doing its own nested
`jsr GetEa` — a real win, not a wash, on every fast-pathed mode (`fmove.x
(a0),fp0` 736→719, `fmove.d (a0),fp0` 881→864, `(a0)+`/`-(a0)` 921→916/
923→918, `(4,a0)` 924→907, Dn-direct word/byte/long 936→921/926→909/
932→905 — see `README.md`'s `#8` row for the full writeup). Caught one
real mistake by measuring rather than trusting the logic: the first
version dispatched the 5 modes via a linear `cmp`/`bcc` chain, which made
`(An)+`/`-(An)`/`(d16,An)` *slower* than before (each pays for every
earlier mode's comparison in the chain) — fixed by switching to a small
jump table (O(1) to reach any mode, matching `GetEa`'s own dispatch
shape), which is what actually delivers the uniform win above. **Does
NOT unblock `#7`**, worth being explicit about since it's the obvious
next question: `#8`'s fast path still reaches into the *same* fixed-
offset `OSTACKAN`/`OSTACKDN` frame (`GETEAREGISTER`'s bitfield extraction
+ a runtime register-number index, unchanged) rather than introducing
the smaller, fixed-shape frame `#7`'s writeup speculated might appear —
that would be a different, larger change (the EA fast path would need
its own dedicated register set, not just inline the same lookup), not
something this row's scope included. `#7` remains ❌/blocked until
something actually does that.

`#9` (transcendental fast paths) is done, scoped down by one piece: `ftwotox`
with an integer operand, `fetox(0)`/`flogn(1)`, `fsqrt` at 0/1, and `fmul`/
`fdiv` by `+-1`/a power of two all landed (see `README.md`'s `#9` row for
the full writeup and measured numbers — `fdiv`'s power-of-two case is the
biggest single win on the checklist so far: 5744→862 cycles, avoiding
`DIV64` entirely). `ftentox` with an integer operand is explicitly NOT
given the same "bump the exponent" treatment — that's a base-2-only trick,
and a correct base-10 equivalent (binary exponentiation off the constant
ROM's existing powers-of-ten entries) is real but meaningfully bigger scope
than anything else in this row, left as a candidate follow-up. Every new
fast path was verified bit-exact against the host reference (register-
direct vectors appended to `vectors/ops.txt`/`src/ops.asm` in their
existing lockstep convention — no new probe infrastructure needed, since
everything here is register-to-register) before being counted as done, and
every ordinary (non-matching) input still pays only a small, flat, measured
tax for the new checks (`fmul`/`fdiv` +12, `fetox`/`flogn` +12-14, `fsqrt`
+26, `ftwotox` +64 worst case) with zero change to its result.

`#10` (native transcendentals) is in progress — this is the biggest row on
the checklist by far (14 named functions, several needing a real numerical
algorithm rather than a bit-trick), so it's landing in pieces, each fully
verified and measured on its own rather than held back for one giant
commit. Motivation this time is portability, not speed, per the user:
dropping `mathieeedoubtrans.library` entirely means femu's transcendentals
no longer need AmigaOS, so this can in principle run on any 68k target.

Shared infrastructure landed first: `src/utils/nativemath.asm` has thin
`jsr`/`rts` wrappers (`NativeFadd`/`NativeFsub`/`NativeFmul`/`NativeFdiv`)
around the existing `FE_FADD`/`FE_FMUL`/`FE_FDIV` macros, so a
transcendental's range-reduction/polynomial code can chain several
arithmetic steps via plain calls instead of inlining each macro's full
body at every step — deliberately the opposite choice from those macros
staying inlined at their OWN hot call sites, since this code is cold
(reached once per trap, not once per arithmetic step within one).

`fsqrt`'s general case is done (the `#9` fast path for 0/1 stays; see
`README.md`'s `#10` row for the full writeup): `NativeFsqrt` does Newton-
Raphson on the reciprocal square root, verified in Python before any
assembly was written, bit-exact against the host `sqrt()` across 8 new
vectors spanning `1.5e-10` to `1.5e10`. Slower than the old library call
(980 (stub) → 14092-15385, no longer a `(stub)` approximation) but that's
expected and not the point — zero AmigaOS dependency for this op now, at a
real, fully-known cost instead of an excluded one.

`fetox`'s general case is also done now (see `README.md`'s `#10` row for
the full writeup): `NativeFexp` does standard range reduction
(`x = k*ln(2)+r`) plus a 16-term Horner-evaluated Taylor polynomial for
`e^r`, then `e^x = e^r * 2^k` via an exponent bump. Landing it surfaced
and fixed two real, pre-existing bugs that had nothing to do with `fetox`
specifically:

1. **`d7` is `INSTRUCTION`** (`src/utils/constants.asm`: `INSTRUCTION
   equr d7`) — the live decoded opcode word every handler's
   `GETREGISTER` reads *after* returning. A native-math loop counter
   parked in `d7` (both the Horner loop here and `NativeFsqrt`'s
   pre-existing iteration counter) corrupts that opcode word, so
   `GETREGISTER` decodes the *wrong* destination FPn and the correct
   result gets written there instead of to the real destination —
   which, for the existing `fp0,fp0` test vectors, looked exactly like
   "the op silently didn't run" rather than "wrong answer". Fixed by
   moving both loop counters into memory. If you write another native-
   math routine with a loop in it: **never put the counter in `d7`.**
2. **`FE_FADD` (shared by `fadd` *and* `fsub`) silently discarded the
   result's sign** for any case reaching `MainBody`'s `DiffSigns`/
   `SameSign` paths — `bfins d6,d0{0:1}` only inserts `d6`'s bit 0, but
   the sign there is built as `d6 = ... & $80000000` (a bit31 value, so
   bit 0 is always 0). Every add/sub whose true result is negative came
   out positive. Never caught before because no existing vector
   exercised that path with a negative result. Fixed (`or.l d6,d0`,
   matching `FE_FMUL`'s own correct convention). Two new `fsub`/one new
   `fadd` vector now pin this.

Also bumped the bench harness's vector/opcode buffers from a hardcoded 64
to 128 (`bench/src/harness.c`) — they silently truncated past 64 with no
error, so the 5 new `fetox` vectors added past that point weren't
actually running even though the suite reported all-MATCH.

`flogn`'s general case is also done now (see `README.md`'s `#10` row for
the full writeup): `NativeFlogn` reads `x = m*2^e` directly off the
operand (free, no shifting), computes `ln(m)` via the atanh series
`s=(m-1)/(m+1)`, `ln(m)=2*s*(1+s^2/3+s^4/5+...)` with `m` first centered
against `sqrt(2)` to keep `s` small enough for a 13-term series, then
adds `e*ln(2)` (reusing `NativeFexp`'s own `ExpLn2` constant). Landing
its NaN-producing special cases (negative `x`, `-Inf`) surfaced a real
bench harness bug: every `MATCH`/`DIFFER` check used a bare `==`, which
is *always* false for a correct NaN result (IEEE: `NaN != NaN`) — fixed
with a `values_match()` helper used at all 5 comparison sites in
`bench/src/harness.c`, not just this row's new vectors.

`ftwotox`/`ftentox`'s general case and `flog2`/`flog10` are also done
now (see `README.md`'s `#10` row for the full writeup) — cheap
derivations once `fetox`/`flogn` were native, no new algorithm needed:
`b^x = e^(x*ln(b))` (multiply by `ExpLn2`/new `ExpLn10`, then
`NativeFexp`) and `log_b(x) = ln(x)/ln(b)` (`NativeFlogn`, then
multiply by `ExpInvLn2`/new `ExpInvLn10`). Each got its own Inf/NaN
(and, for the logs, zero/negative) special-case ladder, duplicated per
op rather than shared. Unplanned bonus: `flog2`'s long-standing 1-ULP
discrepancy against the host reference (there since `#9`, from the old
`log10(x)/log10(2)` library-stub composition rounding differently than
glibc's direct `log2()`) is simply gone now that `flog2` computes
`ln(x)*(1/ln(2))` instead — the whole bench suite is bit-exact with no
discrepancies left anywhere, for the first time this session.

`fsinh`/`fcosh`/`ftanh` are also done now (see `README.md`'s `#10` row
for the full writeup): all three derive from `fetox`'s `NativeFexp`,
computing `e^x` and `e^-x` and combining (`sinh=(e^x-e^-x)/2`,
`cosh=(e^x+e^-x)/2`, `tanh=(e^x-e^-x)/(e^x+e^-x)` -- the `/2` cancels
in tanh's ratio, so it's never computed there). Each op's special-case
ladder reflects its own symmetry (odd/even/bounded) rather than reusing
fetox's verbatim. One pre-existing vector, `fcosh(9.43)`, shows a real
1-ULP difference from the host reference, but checked against an
80-digit exact `Decimal` value, femu's answer is the one actually
closer to the truth -- the host libm has the error here, not us.

`fsin`/`fcos` are also done now (see `README.md`'s `#10` row for the
full writeup) -- the first of the two pieces in this row needing a real
new algorithm, not a derivation. Standard quadrant range reduction
(`x = n*(pi/2)+r`, `n = round(x*2/pi)`, `|r|<=pi/4`) then separate
11-term Horner-evaluated Maclaurin polynomials for `sin(r)`/`cos(r)`,
then the usual quadrant table turns `(sin(r),cos(r))` back into
`(sin(x),cos(x))` -- one shared `NativeFsincos` computes both, since
`fsin`/`fcos` (and the future `fsincos`) all need the identical
reduction.

Caught a real bug in this row's own tooling before it shipped: the
Python script generating the Maclaurin coefficients' extended-hex
constants forgot the alternating `+,-,+,-,...` sign a sin/cos Taylor
series needs -- every other series in `#10` (`e^x`, `atanh`) happens
to have all-positive coefficients, so there was nothing to copy the
mistake from. Found by hand-deriving the expected polynomial value at
each partial Horner step in Python and comparing against a register-
level trace of the assembly; agreed exactly through the first term and
only diverged once a should-be-negative coefficient's wrong sign
accumulated, pointing at the constants rather than the loop. Fixed by
regenerating all 22 `SinC*`/`CosC*` constants with the sign restored.

`ftan`/`fsincos` are also done now (see `README.md`'s `#10` row for
the full writeup) -- both cheap derivations once `fsin`/`fcos` landed.
`ftan(x)=sin(x)/cos(x)` costs nothing extra since `NativeFsincos`
already returns sin/cos in exactly the dst/src layout `NativeFdiv`
wants. `fsincos` calls `NativeFsincos` once and writes both results to
the real 68881 opcode's two destination-register fields (sin/"FPs",
cos/"FPc"), with a small dedicated probe (`fsincos_probe.asm`/
`run_fsincos_probe`) added since -- like `fmove_probe.asm`'s own
reason for existing -- a two-register write doesn't fit `vectors/
ops.txt`'s single-result convention. Caught one real `vasm` error
immediately (not a logic bug, a straight-up label collision): using
`.IsNan` as a local label name in `fsincos.asm`'s own NaN branch
collided with `SETCC`'s own internal `.IsNan:` label once both expand
under the same `FsincosHandler` global scope -- renamed to `.GotNan`.

`fatan` is also done now (see `README.md`'s `#10` row for the full
writeup) -- the second and last piece in this row needing a real new
algorithm, since `atan`'s own Gregory series converges too slowly
(geometric decay, not factorial like `sin`/`cos`/`e^x`) to use
directly. Two chained range-reduction identities first: `atan` is odd
(work with `|x|`, sign reapplied at the end); `|x|>1` reduces via
`atan(x)=pi/2-atan(1/x)`; `|x|>tan(pi/8)` reduces further via
`atan(x)=pi/4+atan((x-1)/(x+1))`, leaving `|x|<=tan(pi/8)~=0.4142` for
a 25-term Horner-evaluated series (verified in Python first, same
discipline as every other row -- needed nearly twice `flogn`'s term
count purely because the Gregory series decays only geometrically, not
a mistake). `pi/2` reuses `NativeFsincos`'s own `SinCosHalfPi`; `pi/4`
is one new constant. `+-Inf` constructs a sign-kept `+-pi/2` (unlike
every other Inf case in this row, `atan` has real horizontal
asymptotes, not an undefined oscillation) and an actual NaN passes
through unchanged. No new bugs this time -- the algorithm and term
count were nailed down in Python before any assembly was written.

`fasin`/`facos` are also done now (see `README.md`'s `#10` row for the
full writeup) -- both cheap derivations, no new algorithm needed, the
last two functions in this row. `NativeFasin` computes
`asin(x)=atan(x/sqrt(1-x^2))` entirely from already-landed pieces;
`facos.asm` derives `acos(x)=pi/2-asin(x)` at the op-handler level
rather than needing its own `NativeFacos`, the same move `ftan.asm`
already made from `NativeFsincos`. One real precision pitfall caught
in Python first: `1-x^2` computed the obvious way (`x*x` then `1-`)
loses precision catastrophically as `|x|->1`; factored instead as
`(1-x)*(1+x)` -- algebraically identical, but neither sub-expression
is a near-cancellation -- cut the measured worst-case error from
~4.7e-15 to ~2.2e-16 (double precision, 200000 random samples) before
any assembly was written. `asin` is odd (zero self-identical), but
`acos` is neither odd nor even, so `facos.asm` special-cases every
boundary directly (`0->pi/2`, `+1->0`, `-1->pi`, the last an exact
exponent-bumped double of `pi/2`, not a second independently-rounded
constant). Both ops special-case `|x|==1` themselves (handing it to
`NativeFasin` would divide by a zero `sqrt`) and treat `|x|>1`/`+-Inf`
alike as out-of-domain, constructing a NaN; an actual NaN passes
through unchanged.

**This closes out checklist `#10`.** All 14 originally named
functions, plus `fsqrt` found along the way, now run without
`mathieeedoubtrans.library`/`mathieeedoubbas.library` at all --
femu's transcendentals no longer need AmigaOS, the row's whole point
from the start.

Asked (not assumed) right after `#10` closed: how do the native
transcendentals compare to the old library-call path? Answer: there's
no real comparison available -- the bench harness always intercepted
the library call and never counted cycles inside it, so the old
"(stub)" numbers (954-1030 cycles, every op) were pure femu-side call
overhead with the real library math excluded entirely, and the real-
hardware harness (`ftest.asm`) is still the known-broken one from
`CLAUDE.md`'s ground truth. What IS real and measured: `#10`'s own
chaining cost. `fatan` alone costs 24k-36k cycles; `fasin`/`facos`
chain `fatan` + `fsqrt` + four more ops and land at ~55k -- the full
cost of everything chained, no amortization, same pattern in
`fsinh`/`fcosh`/`ftanh` (2x `fetox`) and `ftwotox`/`ftentox`/`flog2`/
`flog10` (1x `fetox`/`flogn` + a multiply). This is now `#13` on the
checklist (CORDIC, or a shorter per-function series that skips the
detour through `fatan`/`fetox`/`flogn`) -- not started, not next.

`#11` (fmovem bulk register move fix) is next: the only row left
untouched from before `#10` started, now that `#13` has been recorded
rather than chased immediately.

**Before assuming something's a bug: check for concurrent work.** More
than once, a checklist row turned out to already be done on a pushed
`perf/*` branch (or even already merged to `master`) by a different,
concurrent session -- what looked like a regression (an `ifd NOMATHLIB`
guard missing from an op file) was actually another session correctly
finishing `#2`. Before "fixing" something that looks wrong in a file a
checklist row doesn't mention touching, run `git log --oneline --all`
and `git ls-remote --heads origin` to check whether a sibling branch or
a newer `master` already explains it.
