;
; fsin emulation
;
FsinHandler

	; Debug instruction
	WRITEDEBUG		#.DEBUGOP,INSTRUCTION

	; Increment PC
	INREMENTPC		#$04

	; Get data (extended-format operand, checklist #4)
	GETDATALENGTH	d0
	GETEAVALUE		d0,d1,d2

	; Native sin(x) (checklist #10): no library call. sin is odd, so
	; zero (either sign) is self-identical (sin(0)=0) -- same bits
	; back out, no computation. Inf is NOT self-identical here, unlike
	; e.g. fsinh's own zero/Inf fast path: sin(+-Inf) is undefined
	; (the function oscillates forever as x->+-Inf), so it constructs
	; a NaN; an actual NaN passes through unchanged, discriminated the
	; same way SETCC itself does (mantissa isn't the clean explicit-
	; bit-only Infinity pattern). Everything else goes through
	; NativeFsincos (src/utils/nativemath.asm), shared with fcos.asm.
	bfextu			d0{1:15},d6
	beq.w			.FastDone
	cmp.l			#32767,d6
	bne.s			.Finite
	cmp.l			#$80000000,d1
	bne.w			.FastDone
	tst.l			d2
	bne.w			.FastDone
	move.l			#$7fff0000,d0
	move.l			#$ffffffff,d1
	move.l			#$ffffffff,d2
	bra.w			.FastDone
	.Finite:
	jsr				NativeFsincos
	.FastDone:
	GETREGISTER		d5
	MOVEDNTOFPN		d5,d0,d1,d2

	; Set condition codes
	SETCC			d0,d1,d2

	; Done
	rts

	; Debug constants
	.DEBUGOP:
	dc.b 			"fsin %08lx",10,0
	even
