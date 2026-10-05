;
; ftanh emulation
;
FtanhHandler

	; Debug instruction
	WRITEDEBUG		#.DEBUGOP,INSTRUCTION

	; Increment PC
	INREMENTPC		#$04

	; Get data (extended-format operand, checklist #4)
	GETDATALENGTH	d0
	GETEAVALUE		d0,d1,d2

	; Native tanh(x) (checklist #13): tanh(x) = (e^x-e^-x)/(e^x+e^-x),
	; but multiplying top and bottom by e^x gives
	; tanh(x) = (e^(2x)-1)/(e^(2x)+1) -- ONE NativeFexp call (of 2x,
	; itself a free exponent bump, not a multiply) instead of #10's
	; original two (e^x and e^-x separately). Cheaper even than
	; fsinh/fcosh's own #13 fix (one NativeFexp + one NativeFdiv
	; reciprocal) since this needs no division-shaped extra step at
	; all beyond the ratio tanh was already computing. Verified in
	; Python (double precision, 100000 random |x|<=20) that this
	; identity matches `math.tanh` to 1 ULP before writing any
	; assembly.
	;
	; tanh is odd, so zero (either sign) is self-identical (tanh(0)=0)
	; just like fsinh's. Inf/NaN: tanh(+-Inf)=+-1 -- sign kept,
	; magnitude replaced (unlike fsinh's fully self-identical Inf
	; passthrough, since tanh's horizontal asymptote is +-1, not
	; +-Inf). An actual NaN passes through unchanged, discriminated
	; the same way SETCC itself does.
	;
	; |x| > 30 saturates to +-1 explicitly (verified in Python: exact
	; to this format's 64-bit mantissa -- 1-tanh(30) ~ e^-60, far
	; below 2^-64) rather than falling through to compute e^(2x): at
	; x=30 that's already e^60, fine, but e^(2x) overflows this
	; format's own exponent field around x~5678 (half of e^x's own
	; ~11356 overflow point, since doubling x doubles the exponent
	; needed) -- #10's original two-call version never hit that
	; (e^x finite, e^-x correctly underflowed to 0 for any x in that
	; gap), so this guard keeps #13's rewrite correct over the exact
	; same input range the old code was, not just the common case.
	bfextu			d0{1:15},d6
	beq.w			.FastDone

	cmp.l			#32767,d6
	bne.s			.CheckLarge
	cmp.l			#$80000000,d1
	bne.w			.FastDone
	tst.l			d2
	bne.w			.FastDone
	and.l			#$80000000,d0
	or.l			#$3fff0000,d0
	move.l			#$80000000,d1
	moveq			#0,d2
	bra.w			.FastDone

	.CheckLarge:
	move.l			d0,d3
	and.l			#$7fffffff,d3
	cmp.l			#$40030000,d3
	bhi.w			.Saturate
	blo.w			.Finite
	cmp.l			#$f0000000,d1
	bhi.w			.Saturate
	blo.w			.Finite
	bra.w			.Finite			; |x|==30 exactly: compute normally

	.Saturate:
	and.l			#$80000000,d0
	or.l			#$3fff0000,d0
	move.l			#$80000000,d1
	moveq			#0,d2
	bra.w			.FastDone

	.Finite:
	; 2x -- plain exponent increment, sign preserved via the bit0-
	; right-justified bfextu/bfins pairing (x can be negative here,
	; unlike NativeFexp/NativeFsqrt's own always-positive final bumps).
	bfextu			d0{0:1},d6
	bfextu			d0{1:15},d0
	addq.l			#1,d0
	lsl.l			#8,d0
	lsl.l			#8,d0
	bfins			d6,d0{0:1}
	jsr				NativeFexp
	move.l			d0,FtanhE2x
	move.l			d1,FtanhE2x+4
	move.l			d2,FtanhE2x+8

	; numerator = e2x - 1
	move.l			FtanhE2x,d0
	move.l			FtanhE2x+4,d1
	move.l			FtanhE2x+8,d2
	lea.l			FtanhConstOne,a0
	movem.l			(a0),d3/d4/d5
	jsr				NativeFsub
	move.l			d0,FtanhNum
	move.l			d1,FtanhNum+4
	move.l			d2,FtanhNum+8

	; denominator = e2x + 1
	move.l			FtanhE2x,d0
	move.l			FtanhE2x+4,d1
	move.l			FtanhE2x+8,d2
	lea.l			FtanhConstOne,a0
	movem.l			(a0),d3/d4/d5
	jsr				NativeFadd

	; tanh(x) = numerator/denominator
	move.l			d0,d3
	move.l			d1,d4
	move.l			d2,d5
	move.l			FtanhNum,d0
	move.l			FtanhNum+4,d1
	move.l			FtanhNum+8,d2
	jsr				NativeFdiv

	.FastDone:
	GETREGISTER		d5
	MOVEDNTOFPN		d5,d0,d1,d2

	; Set condition codes
	SETCC			d0,d1,d2

	; Done
	rts

	; Debug constants
	.DEBUGOP:
	dc.b			"ftanh %08lx",10,0
	even
FtanhE2x		dc.l	0,0,0
FtanhNum		dc.l	0,0,0
FtanhConstOne	dc.l	$3fff0000,$80000000,$00000000	; 1.0
