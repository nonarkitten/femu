# Measuring a speedup

femu only really runs on Amiga hardware, WinUAE, or FS-UAE — none of which
give you a scriptable, CI-friendly cycle count, and none of which are
available in a typical dev sandbox (no m68k toolchain, no Kickstart ROM).
So instead of "run it on a real Amiga and eyeball it", we measure with a
**headless 68K CPU emulator embedded in a small host-side C harness**. This
gives exact retro cycle counts, builds with a stock host `gcc`, and produces
a diffable number for every checklist row in `README.md`.

## Why this approach and not WinUAE/FS-UAE

- WinUAE/FS-UAE need a Kickstart ROM (copyrighted, not redistributable) and
  a full AmigaOS boot just to open `dos.library` and friends — massive
  overhead for what is, at its core, a question about how many cycles
  `HandleException` burns on one opcode.
- femu's exception handler doesn't need AmigaOS at all to run: it installs
  itself at vector 11 (`$2c`, "Line 1111 Emulator") and does its work with
  plain register/memory access. A bare CPU core with a synthetic vector
  table is sufficient to execute it.
- A pure-C, no-ROM 68K core builds anywhere (this sandbox included) and can
  run thousands of opcode trials in milliseconds — good enough to make "run
  the benchmark" a normal step in every branch, not a special occasion that
  requires a human with real hardware.

## The harness (`bench/`, to be built as checklist item `#0`)

1. **Core**: [Musashi](https://github.com/kstenerud/Musashi) — a portable,
   MIT-licensed, cycle-counting 68000/68010/68020/68030/68040 emulator core
   in plain C. No ROM, no OS, just an address space and a CPU. Vendor it
   into `bench/vendor/musashi/`.
2. **Memory image**: assemble femu normally (`vasmm68k_mot` output is a
   flat hunk; for the harness we link/convert the relevant code hunks —
   `femu.asm`'s `HandleException` plus everything it pulls in — into a flat
   binary loaded at a fixed base, e.g. `$1000`). No AmigaOS: the handful of
   remaining library calls (`_LVOIEEEDPAdd` and friends) are stubbed at
   fixed addresses in the harness — either a native double implementation
   (so correctness can be judged) or a trap back into the C harness that
   fails the run loudly, so we always know whether an op is still going
   through a stub.
3. **Vector table**: harness builds a synthetic 256-entry vector table with
   vector 11 pointed at `HandleException`, everything else pointed at a
   halt stub.
4. **Driver loop**: for each golden test vector (see below), the harness
   pokes operands into the right place (FP registers / memory per the
   addressing mode under test), writes the F-line opcode word(s) at a known
   PC, resets `m68k_cycles_run()`'s counter, calls `m68k_execute(n)` until
   the handler's `rte` returns control past the opcode, and records the
   cycle delta. This isolates *emulator* cost from harness bookkeeping.
5. **Report**: emit `bench/results/<cpu>-<branch>.json` — one row per
   (opcode, operand class): cycles, and whether the result was bit-exact
   against the golden expected value.

## Golden test vectors (`bench/vectors/`)

- One JSON file per opcode: operand(s), source data format (B/W/L/S/D/X/P),
  and the **expected result**, precomputed once on the host in C
  `long double` / Python `decimal` — not by calling the Amiga math
  libraries, so the vectors stay valid even after we've dropped that
  dependency (checklist `#2`).
- Cover the boring case (normal finite operands) *and* the edge cases that
  motivate several checklist rows: ±0, ±Inf, NaN, denormals, exact powers
  of two, operands equal to 1, single-vs-double precision variants
  (`fsadd`/`fdadd`/plain `fadd`), and a couple of common addressing modes
  per op (`Dn`, `(An)`, `(An)+`, `d16(An)`, immediate).
- `src/ftest.asm`'s existing cases are a starting point — port their
  operand/expected pairs in, then fix `src/ftest.asm` itself (the dead
  code after the early `rts` in `FtestInit`'s caller) so the real-hardware
  smoke test isn't silently skipping itself.

## Baselines and comparison

- Run the harness against `master` once per CPU target we care about
  (68020, 68040) and commit the result as
  `bench/baseline/<cpu>.json`.
- Every `perf/<id>-<slug>` branch re-runs the harness and diffs against
  that baseline: per-opcode delta and a total weighted by a rough
  "how often does real code use this" profile (arithmetic ops weighted
  far higher than rarely-used transcendentals) so a win on `fadd` isn't
  drowned out by noise on `facos`.

## What counts as "an actual improvement"

- Net weighted cycle reduction on the CPU target(s) the idea claims to
  help, **and**
- Zero correctness regressions (bit-exact vs. the golden vectors) on
  every opcode touched, **and**
- No silent regression on a CPU target guarded by `ifd`/`ifnd` that the
  idea wasn't supposed to touch (run the harness for 020 and 040 both,
  even if the idea is "a 040 thing").

If a change helps one opcode and hurts another, that's not an automatic
merge — say so explicitly in the checklist row's Result column and let the
net weighted number (or a human) decide.

The real-hardware/WinUAE run of `src/ftest.asm` stays as a final
human-in-the-loop smoke test before merging a branch back to `master` —
belt and suspenders — but it is not the gate; the harness is.

## Running it

```
cd bench
make            # builds the harness against vendored Musashi
./femu-bench --cpu 020 --branch $(git branch --show-current) \
    --baseline baseline/020.json --vectors vectors/
```

(`bench/` doesn't exist yet — building it is checklist item `#0` in
`README.md`. Everything above is the design to implement, not a
description of code that's already there.)
