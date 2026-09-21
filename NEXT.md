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

`#0` (the `bench/` harness) and `#1` (native `MUL64`/`DIV64`, real
`FE_FMUL`/`FE_FDIV`) are both ✅. Next up: `#2` (make `NOMATHLIB` the
default) and `#3` (relaxed IEEE) both depend only on `#1` and are
unblocked — pick either. `#4` (native extended-precision internal
representation) and `#9`/`#10` (transcendental fast paths / native
transcendentals) also depend on `#1` and are fair game.

Two things worth knowing before touching `fdiv` again: its `NOMATHLIB`
cost (~4400-4700 cycles) is dominated by a 54-iteration one-bit-at-a-time
division loop — deliberately the simple-and-correct version, not the
fast one (see `#1`'s row in `README.md`). A hardware-`divu.l`-seeded
division algorithm is a good candidate for its own future checklist row.
