;
; fsmul/fsglmul/fsdiv/fsgldiv/FPCR-forced-single probe opcodes for
; checklist item #5's single-precision fast path (see ../../README.md
; row #5). Register-to-register only, same lockstep-by-position
; convention as ops.asm and fmove_probe.asm -- harness.c's
; run_fsmul_probe reads this blob positionally.
;
; vasm's m68881 mnemonic table only recognizes fsmul/fsglmul/fsdiv/
; fsgldiv under a 68040/Apollo target (see bench/Makefile's dedicated
; build rule for this file), not under -m68881 alone -- the encoded
; opcode itself is identical regardless of which target assembled it,
; and traps through vector 11 on the headless 68020 core exactly like
; every other F-line opcode here, so this doesn't change what's
; actually being measured.
;
	fsmul.x		fp1,fp0
	fsglmul.x	fp1,fp0
	fmul.x		fp1,fp0
	fsdiv.x		fp1,fp0
	fsgldiv.x	fp1,fp0
	fdiv.x		fp1,fp0
