# CLAUDE.md — working agreement for femu

femu is a 68K-assembly F-line exception handler that emulates a 68881/68882
FPU in software for Amigas that don't have one. This file is the durable
"how we work here" doc. For *what* we're doing right now, see `README.md`
(the optimization checklist) and `NEXT.md` (one-paragraph kickoff for a
fresh session).

## Prime directive

Keep femu **small, fast, correct, and testable** — in that order of
tie-breaking when two of them conflict, correct always wins, and testable
beats fast (an unmeasured "optimization" is a guess, not a result).

## Ground truth about this repo

- Pure 68K assembly, assembled with `vasmm68k_mot` + `vlink` (see
  `Makefile`). There is no C, no m68k toolchain in a typical dev sandbox —
  assume you cannot assemble or run the real binary locally. Build the
  host-side benchmark harness (see `BENCHMARK.md`) in portable C instead;
  that's how we iterate without real hardware.
- Internal FP registers (`RegFpn`) are stored as plain IEEE-754 doubles
  (`d0`=hi32, `d1`=lo32), not the CPU's native 80-bit extended format.
  Conversion happens at the boundary (`src/utils/type.asm`:
  `ExtendedToDouble` / `DoubleToExtended`, etc.) every time a value crosses
  between a real FPn register and memory.
- Most arithmetic (`fadd`, `fmul`, `fdiv`, ...) and essentially all
  transcendentals (`fsin`, `fetox`, `ftwotox`, ...) call out to
  `mathieeedoubbas.library` / `mathieeedoubtrans.library` via `jsr`. The
  `NOMATHLIB` build define is meant to switch to native macros
  (`FE_FADD`, `FE_FMUL`, ...) instead, but several of those are
  unfinished — e.g. `FE_FMUL` in `src/ops/fmul.asm` multiplies mantissas
  with `ADD64` (a bug, not a placeholder that merely underperforms).
- `EmulateInstruction` (`src/utils/op.asm`) decodes via a 3-level jump
  table, then `GETEAVALUE`/`src/utils/ea.asm` (709 lines) decodes the
  effective address for every 68020+ addressing mode on every trap, even
  though the overwhelming majority of real code uses `Dn`, `(An)`,
  `(An)+`, `-(An)`, `d16(An)`.
- Every F-line trap does a full `movem.l d0-d7/a0-sp` save/restore
  (`PREHANDLEEXCEPTION`/`POSTHANDLEEXCEPTION` in
  `src/utils/fhandler.asm`) and always exits via `rte`, even when the
  very next instruction is another FPU opcode.
- `src/ftest.asm` is the only existing test harness and it only runs on
  real hardware or WinUAE/FS-UAE (prints via `dos.library`). It currently
  has dead code: `FtestInit`/`FtestMathBase`/`FtestMathTrans`/
  `FtestCompare`/`FtestExit` are called *after* an unconditional `rts` —
  they never run. Don't trust "it passes ftest" until that's fixed.
- `ISSUES.md` has a per-opcode status table from the original author —
  read it before touching an op; it often already names the problem.
- The Apollo 68080 (`CPU080`/`VECTOR080`) path is a separate story: when
  `VECTOR080` is defined, hardware FPU vectors are installed directly
  (`DirectOpVectorsAligned`) and this software emulator is mostly
  bypassed for that CPU. Don't let software fast-paths regress it, but
  don't spend optimization effort chasing it either — it already has a
  real FPU.

## How we work an optimization idea

1. One idea, one branch, off `master`, named `perf/<id>-<slug>` matching
   the `#<id>` row in `README.md`'s checklist.
2. Implement it under the relevant `ifd`/`ifnd` guards so it never
   silently changes behavior for a CPU target it wasn't meant for
   (`CPU020`/`CPU040`/`CPU080`, `NOMATHLIB`, `FPN080`/`FPC080`/`FPSR080`).
3. Run the benchmark harness (`BENCHMARK.md`) before *and* after your
   change, on the same golden vectors, same CPU target(s) as the idea
   claims to help.
4. Update the checklist row in `README.md`:
   - Net win, no correctness regression → mark it ✅ merged, record the
     measured delta, merge the branch into `master`.
   - No measurable win, or a correctness regression you can't fix within
     scope → mark it ❌, ~~strike the idea's name~~, write one sentence on
     *why* it didn't pan out, leave the branch pushed and unmerged.
5. **Never delete a branch or force-push over one**, win or lose — a
   rejected idea's code is a record that it was tried, and it may become
   relevant again once a dependency (another row) lands.
6. Go back to `master`, pick the next row whose `Depends on` column is
   already satisfied, repeat.

Don't batch unrelated ideas into one branch — you can't attribute a cycle
delta to a change you can't isolate.

## Low-level / assembly practices

- **Measure, don't guess.** "This should be faster" is a hypothesis, not
  a commit message. The benchmark harness exists so every claim in the
  checklist has a number next to it.
- **Document register usage.** Follow the existing convention (see any
  macro in `src/utils/math64.asm` or `src/utils/double.asm`): a header
  comment listing INPUTS / RESULT / scratch registers clobbered. A reader
  should never have to trace a macro body to find out what it destroys.
- **Keep macros flat in hot paths.** This is an interpreter's inner loop;
  a macro that calls three other macros three levels deep is fine for
  cold setup code, expensive when it's expanded per-opcode. Prefer
  inlined, linear code in anything reached on every trap.
- **No speculative abstraction.** Don't generalize an op handler "in case
  we need it for another opcode later" — copy the ten lines when a second
  caller actually shows up. Assembly has zero tolerance for indirection
  that doesn't pay for itself.
- **Trust the CPU guards, extend them, don't remove them.** If your idea
  only makes sense for 68040 or only for the double-precision internal
  format, gate it with `ifd`/`ifnd` like the rest of the file does — do
  not make an optimization that quietly changes 68020 behavior while
  chasing a 68040 win.
- **Relaxed-IEEE work is opt-in, not a silent behavior change.** If an
  idea drops strict NaN/Inf/denormal handling on the fast path, it must
  still produce the *correct* answer for those inputs — either by falling
  through to a correct slow path when a cheap check detects a special
  value, or by an explicit build-time flag the checklist row documents.
  We are not in the business of quietly returning wrong answers faster.
- **Don't touch unrelated TODOs while working a checklist row.** Note
  them, don't fix them inline — that's how a "cycle-count fadd" branch
  turns into an unreviewable diff. File them as a candidate future row
  in the checklist instead.
- **Comment the why, not the what.** The existing codebase already does
  this well in most places (see the header comments) — match that style.

## Where to look

- `README.md` — the optimization checklist (source of truth for status).
- `BENCHMARK.md` — how to measure a change: harness design, how to run
  it, how to read its output, what counts as "an actual improvement".
- `NEXT.md` — the one-paragraph state-of-the-world doc; read this first
  in a fresh session, before this file, if you just want to know what to
  do next.
- `ISSUES.md` — the original per-opcode issue list; still accurate for
  "does this op call a library it shouldn't".
