# femu bench harness

Runs femu's real, assembled `HandleException` through a headless Musashi
68020 core (no AmigaOS, no ROM, no real hardware) and reports, per
opcode, the exact number of 68k cycles the trap took plus whether the
result matches a host-computed reference value. See `../BENCHMARK.md`
for the design and rationale; this file is just build/run/troubleshoot.

## Build and run

```
cd bench
make run
```

First build vendors and compiles `vasmm68k_mot` (from
`vendor/vasm`, unless one is already on your `PATH`) and Musashi
(`vendor/musashi`) — both are git submodules, so `git submodule update
--init` first if you cloned femu fresh. Everything lands in `build/`,
which is gitignored (fully regenerable, nothing there is source).

## What it's actually doing

1. `src/bench_wrapper.asm` is assembled (`-Fbin`, no `vlink` involved —
   see `../BENCHMARK.md` for why that's unnecessary here) into a flat
   binary twice: once matching the real `femu.020` build
   (`build/femu020.bin`) and once matching `femu.020m`/`NOMATHLIB`
   (`build/femu020m.bin`). It's a thin, unmodified wrapper around
   `../src/femu.asm` — see the comment at the top of that file for the
   handful of addresses it exposes to the harness.
2. `src/ops.asm` assembles to a flat sequence of real 68881
   register-to-register FP instructions (`fadd.x fp1,fp0`, ...), one
   per row of `vectors/ops.txt`, in the same order. The harness slices
   this into 4-byte opcodes rather than hand-encoding instruction words.
3. `src/harness.c` links against Musashi configured as a plain 68020
   (no FPU), so any F-line opcode we execute traps through vector 11 —
   exactly like real 68020 hardware without a 68881 attached, and
   exactly what `HandleException` is written to handle.
4. For each vector: reset the CPU, point the exception vector table
   (relocated via VBR, away from femu's own code) at
   `HandleException`, poke the operand(s) into femu's own `RegFpn`
   register file, drop the opcode at a fixed test address, and single
   step (`m68k_execute(1)` in a loop) until control returns past the
   opcode — summing real cycles the whole way.
5. femu's `mathieeedoubbas.library`/`mathieeedoubtrans.library` calls
   can't actually run (there's no AmigaOS here), so each library
   function slot is filled with an `ILLEGAL` opcode and answered by an
   `ILLG` callback in the harness that does the equivalent host `libm`
   call and manually pops the return address, the same way an Amiga
   library's `jsr` would. **Cycles spent inside a stubbed call are not
   counted** — there's no real 68k code executing for them — and any
   vector whose run touched a stub is marked `(stub)` in the report.

## Reading a report

```
op                 cycles      match  note
fadd                  642      MATCH  3.3000000000000003 vs 3.3000000000000003 (stub)
fmul                  634      MATCH  27.224999999999998 vs 27.224999999999998 (stub)
```

- **cycles** is real, measured 68020 cycles for everything femu's own
  code did — trap entry, EA/register decode, condition codes, trap
  exit — for a `(stub)` row this **excludes** whatever the real Amiga
  library would have cost internally, so a low number on a `(stub)`
  row is not "fast", it's "we don't know". Only compare `(stub)` rows
  against other `(stub)` rows of the *same op* across branches (the
  femu-side overhead they measure is real and comparable); don't
  compare a `(stub)` row's total against a fully-native row's total and
  conclude one op is cheaper than another.
- **match** is a bit-exact compare against the host reference in
  `reference()` (`src/harness.c`). `DIFFER` isn't necessarily a bug in
  femu — e.g. `flog2` differs by 1 ULP from `log2(x)` because femu
  actually computes it as `log10(x)/log10(2)` (two chained library
  calls), which is mathematically equivalent but numerically distinct.
  Read the actual asm (`../src/ops/*.asm`) before treating a `DIFFER`
  as a regression.

## Current coverage and known limits (read before trusting a number)

This is checklist item `#0` — enough to make every later row
measurable, not the full design in `../BENCHMARK.md`. Specifically:

- **68020 only.** `M68K_CPU_TYPE_68020`, `FLAGS020`-equivalent build.
  68040 (`STACK040`) isn't wired up yet.
- **Register-to-register only, except for one dedicated probe.** Every
  vector in `vectors/ops.txt` uses `fp0`/`fp1` direct addressing
  (`GETDATALENGTH`'s "always double" fast path). No `Dn`, `(An)+`,
  `d16(An)`, or immediate addressing-mode vectors yet — `../BENCHMARK.md`
  calls these out as follow-up coverage. The one exception:
  `src/fmove_probe.asm` + `run_fmove_probe()` in `harness.c` test
  `fmove`/`fmovem` via `(a0)` addressing specifically, built for
  checklist row `#4`'s design pass (see `../DESIGN-04-native-extended-repr.md`)
  — outside the vectors.txt/ops.asm lockstep convention, since it needs
  a populated memory operand rather than just register contents.
- **No single-precision (`fs*`) or extended-precision (`fd*` in the
  40-bit-mantissa sense) variant vectors** — only the plain (double)
  opcode forms in `vectors/ops.txt`.
- **Some Inf/zero-operand vectors exist** (`fadd`/`fmul`/`fdiv` x
  {Inf, 0.0} in a few combinations, added for checklist row `#3`), but
  **no NaN and no denormal vectors** — worth adding if a future row
  actually implements denormal arithmetic (today's denormal-as-zero
  behavior, unchanged since before `#3`, is a known limitation, not
  something these vectors exercise).
- **`vectors/ops.txt` and `src/ops.asm` are hand-kept in lockstep**
  (same row order, one line per row) rather than generated from each
  other. The harness refuses to run if their counts disagree.

## Baselines

`baseline/020.txt` is the harness's own stdout captured against
`master`. Regenerate and diff with:

```
make run > /tmp/after.txt
diff baseline/020.txt /tmp/after.txt
```

A `perf/<id>-<slug>` branch that changes measured behavior updates
`baseline/020.txt` itself as part of its own commit once merged (so it
always reflects `master`'s current numbers), and reports the diff in
the checklist row per `../CLAUDE.md`'s workflow.
