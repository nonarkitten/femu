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

`#0`-`#3` are all ✅ (bench harness; native `MUL64`/`DIV64` + real
`FE_FMUL`/`FE_FDIV`; `NOMATHLIB` made the default for `fadd`/`fsub`/
`fmul`/`fdiv`; the Inf/NaN/zero fast path). Everything depending only on
`#1` is unblocked: `#4` (native extended-precision internal
representation), `#5` (single-precision fast path), `#9`/`#10`
(transcendental fast paths / native transcendentals).

Two things worth knowing before touching `fdiv` again: its cost
(~4400-4700 cycles) is dominated by a 54-iteration one-bit-at-a-time
division loop — deliberately the simple-and-correct version, not the
fast one (see `#1`'s row in `README.md`). A hardware-`divu.l`-seeded
division algorithm is a good candidate for its own future checklist row.

**Before assuming something's a bug: check for concurrent work.** More
than once, a checklist row turned out to already be done on a pushed
`perf/*` branch (or even already merged to `master`) by a different,
concurrent session -- what looked like a regression (an `ifd NOMATHLIB`
guard missing from an op file) was actually another session correctly
finishing `#2`. Before "fixing" something that looks wrong in a file a
checklist row doesn't mention touching, run `git log --oneline --all`
and `git ls-remote --heads origin` to check whether a sibling branch or
a newer `master` already explains it.
