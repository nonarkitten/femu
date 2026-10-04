;
; fsincos dual-register-write probe (checklist #10). fsincos.x writes
; sin to the normal destination field ("FPs") and cos to a separate
; field ("FPc") -- neither vectors/ops.txt's single-result-register
; convention nor ops.asm's lockstep with it can express a two-register
; write, same reasoning as fmove_probe.asm/ea_fastpath_probe.asm's own
; existence. "fp0,fp2:fp1" assembles with FPc=fp2 (cos) and FPs=fp1
; (sin) -- confirmed by decoding the actual encoded extension word
; against GETREGISTER's own two bitfield offsets (the standard Rd
; field at {22:3} for sin, {29:3} for cos) rather than assumed from
; the mnemonic syntax alone.
;
	fsincos.x	fp0,fp2:fp1
