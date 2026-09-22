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

`fdiv`'s cost is still dominated by a one-bit-at-a-time division loop —
deliberately the simple-and-correct version, not the fast one (see
`#1`'s row in `README.md`). A hardware-`divu.l`-seeded division
algorithm is a good candidate for its own future checklist row, now
more valuable than before given `#4`'s iteration-count increase.

`#5` (single-precision fast path), `#9` (transcendental fast paths) and
`#10` (native transcendentals, now unblocked — both its deps, `#1` and
`#4`, are done) are all fair game next.

**Before assuming something's a bug: check for concurrent work.** More
than once, a checklist row turned out to already be done on a pushed
`perf/*` branch (or even already merged to `master`) by a different,
concurrent session -- what looked like a regression (an `ifd NOMATHLIB`
guard missing from an op file) was actually another session correctly
finishing `#2`. Before "fixing" something that looks wrong in a file a
checklist row doesn't mention touching, run `git log --oneline --all`
and `git ls-remote --heads origin` to check whether a sibling branch or
a newer `master` already explains it.
