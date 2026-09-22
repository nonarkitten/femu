;
; Opcode-chaining probe for checklist item #6 (see ../../README.md row #6).
; Each row is a run of real, back-to-back F-line opcodes with NO padding
; between them -- the whole point is to prove femu's trap handler can walk
; straight from one into the next without an intervening rte + re-trap.
; harness.c's run_chain_probe() reads this blob and slices it per row using
; a hand-kept byte-offset/length table (rows aren't a fixed size, unlike
; ops.asm/fmove_probe.asm/fsmul_probe.asm, since a chain of 2 vs. 3 opcodes
; or a trailing non-FPU instruction are different lengths on purpose).
;
; Row 0: two identical reg-to-reg fadds back to back (the simple case).
; Row 1: two DIFFERENT ops back to back (fadd then fmul) -- proves the
;        peek-and-continue check isn't special-cased to one opcode.
; Row 2: three ops back to back -- proves the loop keeps going past a
;        single extra hop, not just "peek once".
; Row 3: one fadd immediately followed by a plain (non-F-line) `nop` --
;        the regression case: chaining MUST stop here and hand control
;        back via the normal rte path instead of misreading `nop` as
;        another FPU opcode.
;
Row0_TwoFadd
	fadd.x		fp1,fp0
	fadd.x		fp1,fp0
Row1_FaddFmul
	fadd.x		fp1,fp0
	fmul.x		fp1,fp0
Row2_ThreeFadd
	fadd.x		fp1,fp0
	fadd.x		fp1,fp0
	fadd.x		fp1,fp0
Row3_FaddThenNop
	fadd.x		fp1,fp0
	nop
