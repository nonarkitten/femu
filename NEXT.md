# Start here

femu is a 68K-assembly software FPU emulator for Amiga. The performance
checklist this project worked through is closed out: every row is either
done, confirmed not viable as scoped, or checked and found unnecessary --
see `README.md`'s "Architecture" section for what that work actually left
behind, not a running log of how it got there (that's git history now;
search commit messages for `#<n>:` if you want the full story on any one
change). Tagged at `v0.15`.

## If you're picking this up fresh

There's no pending row. If you have a new idea, it's the next number
after the last one in git history (check `git log --oneline --all | grep -oE '#[0-9]+'`
for the current high-water mark) -- read `CLAUDE.md` for the working
agreement and the per-idea workflow (branch, implement under a build-time
guard if it's a relaxation, measure before/after with `BENCHMARK.md`'s
harness, update `README.md`, merge on a real win), and `ISSUES.md` for
the original author's per-opcode notes if the idea touches an op that
hasn't been revisited yet.

If you're here to fix a bug instead: `CLAUDE.md`'s "Ground truth about
this repo" section is still accurate and is the fastest way to find
where a given opcode's logic actually lives.
