;
; EA-decode fast-path probe opcodes for checklist item #8 (see
; ../../README.md row #8): exercises the four memory addressing modes
; the fast path added to GetEaValue (src/utils/ea.asm) that aren't
; already covered by fmove_probe.asm's plain (a0) -- (a0)+, -(a0),
; (4,a0), and Dn direct (word/byte/long, to exercise EaDnDirect's
; size-dependent pointer adjustment). harness.c's run_ea_fastpath_probe
; reads this blob by FIXED PER-OPCODE OFFSET (not the plain 4-byte
; lockstep convention ops.asm/fmove_probe.asm/fsmul_probe.asm use) --
; (4,a0) is 6 bytes (a real displacement word), so this can't be
; sliced positionally like those files are.
;
	fmove.l		(a0)+,fp0
	fmove.l		-(a0),fp0
	fmove.l		(4,a0),fp0
	fmove.w		d0,fp0
	fmove.b		d0,fp0
	fmove.l		d0,fp0
