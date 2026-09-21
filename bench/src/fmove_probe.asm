;
; fmove/fmovem memory-operand probe opcodes for checklist item #4's
; design/measurement pass (see ../../README.md row #4 and
; DESIGN-04-native-extended-repr.md). Register-to-register fmove isn't
; here -- it's already a straight copy today (see the design doc for
; why) -- these are specifically the memory-operand paths #4 proposes
; to change. Each line is a fixed, hand-verified 4-byte opcode (no
; extension words for (a0) addressing); harness.c's probe reads this
; blob positionally, same convention as ops.asm.
;
	fmove.x		(a0),fp0
	fmove.x		fp0,(a0)
	fmove.d		(a0),fp0
	fmove.d		fp0,(a0)
	fmovem.x	(a0),fp0-fp3
	fmovem.x	fp0-fp3,(a0)
