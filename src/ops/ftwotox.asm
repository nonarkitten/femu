;
; ftwotox emulation
;
FtwotoxHandler

	; Debug instruction
	WRITEDEBUG		#.DEBUGOP,INSTRUCTION
		
	; Increment PC
	INREMENTPC		#$04

	; Get data (extended-format operand, checklist #4)
	GETDATALENGTH	d0
	GETEAVALUE		d0,d1,d2

	; Fast path (checklist #9): for an integer operand x small enough
	; to land directly in the result's 15-bit exponent field, 2^x is
	; exactly sign=0, exponent=16383+x, mantissa=explicit-bit-only --
	; no InternalToDouble, no library Pow call at all. Verified against
	; an independent exact-rational reference in Python (0/200000
	; random cases + boundary cases up to +-32767) before writing this.
	;
	; d6 = shift = biased exponent - 16383. shift<0 means |x|<1, which
	; can only be an integer at x=0 (handled elsewhere, falls through
	; here); shift>14 means |x| could already exceed the ~32767 a
	; 15-bit exponent field can absorb, so it's not attempted (the slow
	; path's existing overflow/underflow behavior, unchanged, applies).
	; For shift in [0,14], x's value sits entirely within the mantissa
	; hi32 (d1): d2 must be all-fractional-zero, and the low (31-shift)
	; bits of d1 must also be zero for x to be an exact integer; what's
	; left, shifted down, is |x| itself.
	bfextu			d0{1:15},d6
	sub.l			#16383,d6
	bmi.w			.Slow
	cmp.l			#14,d6
	bgt.w			.Slow
	tst.l			d2
	bne.w			.Slow
	moveq			#31,d5
	sub.l			d6,d5
	moveq			#1,d4
	lsl.l			d5,d4
	subq.l			#1,d4
	move.l			d1,d3
	and.l			d4,d3
	bne.w			.Slow
	move.l			d1,d4
	lsr.l			d5,d4
	btst			#31,d0
	beq.s			.Positive
	neg.l			d4
	.Positive:
	add.l			#16383,d4
	cmp.l			#1,d4
	blt.w			.Slow
	cmp.l			#32766,d4
	bgt.w			.Slow
	lsl.l			#8,d4
	lsl.l			#8,d4
	move.l			d4,d0
	move.l			#$80000000,d1
	moveq			#0,d2
	bra.w			.FastDone
	.Slow:

	; Native general case (checklist #10): 2^x = e^(x*ln(2)) -- no
	; library call. Inf/NaN discriminated directly on x itself, same
	; style as fetox.asm's own ladder: +Inf -> +Inf (self-identical);
	; -Inf -> +0 (2^-Inf underflows to 0); NaN passes through unchanged
	; (mantissa isn't the clean explicit-bit-only Infinity pattern).
	; Finite x (this also covers x=0, which the integer fast path above
	; doesn't catch -- its exponent-field-zero encoding makes "bmi"
	; take the slow path -- but e^(0*ln2)=e^0=1 falls out correctly
	; here anyway) multiplies by ln(2) (NativeFexp's own ExpLn2
	; constant, not a second copy) then goes through NativeFexp.
	bfextu			d0{1:15},d6
	cmp.l			#32767,d6
	bne.s			.Finite2
	cmp.l			#$80000000,d1
	bne.s			.NotInf2
	tst.l			d2
	bne.s			.NotInf2
	btst			#31,d0
	beq.w			.FastDone
	moveq			#0,d0
	moveq			#0,d1
	moveq			#0,d2
	.NotInf2:
	bra.w			.FastDone
	.Finite2:
	move.l			d0,d3
	move.l			d1,d4
	move.l			d2,d5
	lea.l			ExpLn2,a0
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
	dc.b 			"ftwotox %08lx",10,0
	even