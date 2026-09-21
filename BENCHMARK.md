   handful of label addresses the harness needs — see the comment at the
   top of that file. Because the flat binary is loaded at address 0 in the
   harness's memory image, which is the same base `vasm` assumed when
   resolving femu's internal absolute references, everything just lines up
   with no relocation step at all.
4. **Vector table**: the harness sets VBR to a synthetic vector table well
   away from femu's own code, and pokes vector 11 to `HandleException`'s
   address. This is exactly what `FemuInit` does on real hardware (reads
   the OS's existing VBR, patches offset `$2c`) — the harness just supplies
   the VBR itself instead of asking AmigaOS for one.
5. **The two Amiga math libraries**: femu (outside `NOMATHLIB` native
   paths) calls `mathieeedoubbas.library`/`mathieeedoubtrans.library` by
   `jsr`ing to `<library base> + <LVO offset>`. There's no AmigaOS here to
   load those libraries, so the harness fills a small region at a chosen
   fake base with `ILLEGAL` ($4AFC) opcodes at every LVO offset femu
   defines (the offsets are femu's own `equ`s in `src/utils/constants.asm`
   — nothing guessed or pulled from the Amiga NDK), and answers each one
   from an `ILLG` instruction callback: read the operands out of
   `d0:d1`/`d2:d3`, do the equivalent host `libm` call, write the result
   back, then pop the return address off the stack and set `PC` there —
   exactly what the real `jsr`/library-return pair would leave behind, just
   with the library's insides replaced by a host function call. **Cycles
   spent inside a stub are not counted** (there's no real 68k code
   executing for them); the report marks any run that touched one so a
   `(stub)` row is never mistaken for a fully-measured one. See
   `bench/README.md` for how to read that.
6. **Driver loop**: for each golden test vector, the harness resets the
   CPU, pokes the operand(s) into femu's own `RegFpn` register file, drops
   the opcode at a fixed test address, and calls `m68k_execute(1)` in a
   loop — real single-stepping, not a large cycle budget — until control
   returns past the opcode, summing the real cycles Musashi reports the
   whole way. Single-stepping (rather than a bigger budget) is what makes
   it safe to stop exactly when the trap handler's `rte` hands control
   back, without ever executing whatever happens to be in memory after
   that point.
7. **Report**: a plain, diffable text table — op, cycles, bit-exact match
   against a host-computed reference, and the `(stub)` marker. No JSON: the
   report is small enough (one row per opcode) that a human-readable table
   loses nothing and needs no dependency to parse.

## Golden test vectors (`bench/vectors/ops.txt`)

- One line per opcode: `op a b` (`b` is `-` for monadic ops), values
  carried over from `src/ftest.asm`'s existing test cases. The harness
  computes the expected result itself from `a`/`b` via the matching C
  operator or `libm` call — there's no separate stored "expected" column,
  since host `double` arithmetic is bit-for-bit the same format femu's
  internal representation already uses.
- Kept in lockstep, by hand, with `bench/src/ops.asm` (same row order, one
  real 68881 instruction per row) rather than generated from each other —
  the set of opcodes under test is small and changes rarely, and
  `harness.c` refuses to run if the two files' row counts disagree.
- **Not yet covered** (see `bench/README.md`'s "current coverage" section
  for the full list): non-register-direct addressing modes, single- and
  extended-precision variants, and NaN/Inf/denormal/zero operands. That
  last group matters a lot for checklist row `#3` (relaxed IEEE) — add
  vectors for it before starting that branch.
- `src/ftest.asm` itself still has a real bug worth fixing independently
  of this harness: `FtestInit`/`FtestMathBase`/`FtestMathTrans`/
  `FtestCompare`/`FtestExit` are called after an unconditional `rts`, so
  they never run on real hardware/WinUAE either. Fixed as part of this
  same checklist item.

## Baselines and comparison

- `bench/baseline/020.txt` is the harness's own stdout captured against
  `master`. A `perf/<id>-<slug>` branch re-runs `make run` and diffs
  against it.
- 68040 (`STACK040`) isn't wired up yet — `#0` covers 68020 only. Extending
  the harness's CPU coverage is itself a fair candidate for a future
  checklist row, not a blocker for starting the others.

## What counts as "an actual improvement"

- Net cycle reduction on the CPU target(s) the idea claims to help, on
  rows that are **not** `(stub)` for that op (a stub's number isn't a real
  baseline to beat — see `bench/README.md`), **and**
- Zero correctness regressions (bit-exact vs. the golden vectors, or an
  explained, expected ULP-level difference like `flog2`'s two-call chain)
  on every opcode touched, **and**
- No silent regression on a CPU target guarded by `ifd`/`ifnd` that the
  idea wasn't supposed to touch.

If a change helps one opcode and hurts another, that's not an automatic
merge — say so explicitly in the checklist row's Result column and let a
human decide.

The real-hardware/WinUAE run of `src/ftest.asm` stays as a final
human-in-the-loop smoke test before merging a branch back to `master` —
belt and suspenders — but it is not the gate; the harness is.

## Running it

```
cd bench
git submodule update --init   # first time only
make run
```

See `bench/README.md` for what the output means and its current limits.
