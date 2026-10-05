;
; fadd/fsub/fmul/fdiv probe opcodes for checklist item #12's relaxed-
; precision (MANTISSA32) internal format (see ../../README.md row #12).
; Register-to-register only, same lockstep-by-position convention as
; ops.asm/fmove_probe.asm/fsmul_probe.asm -- harness.c's
; run_mantissa32_probe reads this blob positionally. Assembled under a
; plain -m68020 -m68881 target like ops.asm (no 68040/Apollo mnemonics
; needed here, unlike fsmul_probe.asm's fsmul/fsdiv).
;
	fadd.x		fp1,fp0
	fsub.x		fp1,fp0
	fmul.x		fp1,fp0
	fdiv.x		fp1,fp0
