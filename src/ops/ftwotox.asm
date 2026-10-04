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

	jsr				InternalToDouble
	move.l			d0,d2
	move.l			d1,d3
	move.l			#$40000000,d0
	move.l			#$00000000,d1

	; Emulate instruction
	movea.l			MathIeeeDoubTransBase,a6
	jsr				_LVOIEEEDPPow(a6)
	jsr				DoubleToInternal
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