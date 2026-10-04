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

`#10` (native transcendentals, deps `#1`/`#4` done) is fair game next;
`#11` (fmovem bulk register move fix) is untouched.

**Before assuming something's a bug: check for concurrent work.** More
than once, a checklist row turned out to already be done on a pushed
`perf/*` branch (or even already merged to `master`) by a different,
concurrent session -- what looked like a regression (an `ifd NOMATHLIB`
guard missing from an op file) was actually another session correctly
finishing `#2`. Before "fixing" something that looks wrong in a file a
checklist row doesn't mention touching, run `git log --oneline --all`
and `git ls-remote --heads origin` to check whether a sibling branch or
a newer `master` already explains it.
