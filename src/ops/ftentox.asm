;
; ftentox emulation
;
FtentoxHandler

	; Debug instruction
	WRITEDEBUG		#.DEBUGOP,INSTRUCTION

	; Increment PC
	INREMENTPC		#$04

	; Get data (extended-format operand, checklist #4)
	GETDATALENGTH	d0
	GETEAVALUE		d0,d1,d2

	; Native general case (checklist #10): 10^x = e^(x*ln(10)) -- no
	; library call. No integer-exponent fast path here (unlike
	; ftwotox's checklist #9 one) -- "bump the exponent" is a base-2-
	; only trick, and a correct base-10 equivalent needs binary
	; exponentiation off the constant ROM's powers-of-ten entries,
	; scoped out of #9 as meaningfully bigger work; this row's job is
	; dropping the library dependency, not that.
	;
	; Inf/NaN discriminated directly on x itself, same style as
	; fetox.asm's own ladder: +Inf -> +Inf (self-identical); -Inf ->
	; +0 (10^-Inf underflows to 0); NaN passes through unchanged
	; (mantissa isn't the clean explicit-bit-only Infinity pattern).
	; Finite x (x=0 included -- e^(0*ln10)=e^0=1 falls out correctly)
	; multiplies by ln(10) (ExpLn10, src/utils/nativemath.asm) then
	; goes through NativeFexp.
	bfextu			d0{1:15},d6
	cmp.l			#32767,d6
	bne.s			.Finite
	cmp.l			#$80000000,d1
	bne.s			.NotInf
	tst.l			d2
	bne.s			.NotInf
	btst			#31,d0
	beq.w			.FastDone
	moveq			#0,d0
	moveq			#0,d1
	moveq			#0,d2
	.NotInf:
	bra.w			.FastDone
	.Finite:
	move.l			d0,d3
	move.l			d1,d4
	move.l			d2,d5
	lea.l			ExpLn10,a0
	movem.l			(a0),d0/d1/d2
	jsr				NativeFmul
	jsr				NativeFexp
	.FastDone:

	; Write results
	GETREGISTER		d5
	MOVEDNTOFPN		d5,d0,d1,d2

	; Set condition codes
	SETCC			d0,d1,d2

	; Done
	rts

	; Debug constants
	.DEBUGOP:
	dc.b 			"ftentox %08lx",10,0
	even
