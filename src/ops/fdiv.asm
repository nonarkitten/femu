;
; d0 - destination high -> dividend fraction high -> remainder high -> result high
; d1 - destination low  -> remainder low
; d2 - source high -> divisor fraction high
; d3 - source low
; d4 - destination exponent -> combined result exponent
; d5 - source exponent -> quotient high (DIV64)
; d6 - scratch -> quotient low (DIV64) -> sticky flag
; d7 - reserved
;
FE_FDIV macro

	; Extract exponents
	bfextu			d0{1:11},d4
	bfextu			d2{1:11},d5

	; Fast path: both operands "ordinary" (finite, nonzero, not a
	; denormal -- exponent in [1,2046])? If so, skip straight past the
	; Inf/NaN/zero ladder below -- see FE_FADD for why this range check
	; is an exact precondition for "the ladder wouldn't have done
	; anything anyway". d6 is free here, before the sign computation
	; both paths do next, so nothing needs restoring.
	move.w			d4,d6
	subq.w			#1,d6
	cmp.w			#2046,d6
	bhs.s			.SpecialCase
	move.w			d5,d6
	subq.w			#1,d6
	cmp.w			#2046,d6
	bhs.s			.SpecialCase

	; Ordinary: compute the sign and go straight to the real divide.
	move.l			d0,d6
	eor.l			d2,d6
	and.l			#$80000000,d6
	bra.w			.MainBody

	.SpecialCase:
	; Result sign = XOR of the operand signs (see FE_FMUL for why this
	; is simpler than FE_FADD's {0:1}-packed convention)
	move.l			d0,d6
	eor.l			d2,d6
	and.l			#$80000000,d6

	; Infinities/NaNs: passed through as-is, matching FE_FADD/FE_FMUL's
	; pragmatic style -- true special-case handling beyond this fast
	; path stays out of scope here too
	cmp.w			#$7ff,d4
	bne.s			.DstExpOk
	bra.w			.Done
	.DstExpOk:
	cmp.w			#$7ff,d5
	bne.s			.SrcExpOk
	move.l			d2,d0
	move.l			d3,d1
	bra.w			.Done
	.SrcExpOk:

	; Zero dividend -> zero (with the XOR'd sign)
	tst.w			d4
	bne.s			.DstExpNoZ
	moveq			#0,d0
	moveq			#0,d1
	or.l			d6,d0
	bra.w			.Done
	.DstExpNoZ:

	; Zero divisor -> infinity (with the XOR'd sign)
	tst.w			d5
	bne.s			.SrcExpNoZ
	move.l			#$7ff00000,d0
	moveq			#0,d1
	or.l			d6,d0
	bra.w			.Done
	.SrcExpNoZ:

	.MainBody:
	; Combined (biased) exponent, before any renormalization below
	sub.w			d5,d4
	add.w			#1023,d4

	; Extract fractions (hidden bit set explicitly, as everywhere else)
	bfextu			d0{12:20},d0
	bfextu			d2{12:20},d2
	bset			#20,d0
	bset			#20,d2

	; DIV64's loop needs its starting remainder below the divisor, which
	; the dividend itself (D) isn't guaranteed to be -- D/V ranges over
	; (0.5,2), so D can be almost 2V. Try D-V once first; if it doesn't
	; borrow, keep it and remember the leading quotient bit was 1 (D>=V),
	; else undo it exactly (the X flag from subx is still live across
	; the branch, so addx.l undoes it precisely) and the leading bit is
	; 0. Sign is stashed first since every register is needed for this.
	move.l			d6,DivSign
	sub.l			d3,d1
	subx.l			d2,d0
	bcc.s			.Lead1
	add.l			d3,d1
	addx.l			d2,d0
	moveq			#0,d5
	bra.s			.LeadDone
	.Lead1:
	moveq			#1,d5
	.LeadDone:
	move.b			d5,DivLead

	; Divide the (now pre-normalized) mantissas -> a 54-bit quotient in
	; d5:d6, remainder left in d0:d1.
	moveq			#0,d5
	moveq			#0,d6
	DIV64			d0,d1,d2,d3,d5,d6

	; Fold the leading bit (from the pre-normalize step, above) back
	; into the quotient, so it reads as a single up-to-55-bit value:
	; bit 54 if the dividend was >= the divisor, else bit 53 is the
	; leading bit. Two fixed cases, so two fixed bitfield offsets --
	; same approach as FE_FMUL's normalization, see there for why.
	tst.b			DivLead
	beq.s			.NoLeadBit
	bset			#22,d5
	.NoLeadBit:
	move.l			d5,QuotientHi
	move.l			d6,QuotientLo
	lea.l			QuotientHi,a0
	btst			#22,d5
	beq.s			.Top53

	.Top54:
	bfextu			(a0){9:21},d0
	bfextu			(a0){30:32},d1
	btst			#1,d6
	beq.s			.NoRoundBit1
	moveq			#1,d5
	bra.s			.HaveRound1
	.NoRoundBit1:
	moveq			#0,d5
	.HaveRound1:
	btst			#0,d6
	bne.s			.Sticky1
	tst.l			d0
	bne.s			.Sticky1
	tst.l			d1
	bne.s			.Sticky1
	moveq			#0,d6
	bra.s			.Round
	.Sticky1:
	moveq			#1,d6
	bra.s			.Round

	.Top53:
	subq.w			#1,d4
	bfextu			(a0){10:21},d0
	bfextu			(a0){31:32},d1
	btst			#0,d6
	beq.s			.NoRoundBit0
	moveq			#1,d5
	bra.s			.HaveRound0
	.NoRoundBit0:
	moveq			#0,d5
	.HaveRound0:
	tst.l			d0
	bne.s			.Sticky0
	tst.l			d1
	beq.s			.NoSticky0
	.Sticky0:
	moveq			#1,d6
	bra.s			.Round
	.NoSticky0:
	moveq			#0,d6

	; Round to nearest, ties to even: d5 = round bit, d6 = sticky
	.Round:
	tst.l			d5
	beq.s			.NoRoundUp
	tst.l			d6
	bne.s			.RoundUp
	btst			#0,d1
	beq.s			.NoRoundUp
	.RoundUp:
	addq.l			#1,d1
	bcc.s			.NoCarry
	addq.l			#1,d0
	.NoCarry:
	btst			#21,d0
	beq.s			.NoRoundUp
	lsr.l			#1,d0
	roxr.l			#1,d1
	addq.w			#1,d4
	.NoRoundUp:

	; Construct result
	bfins			d4,d0{1:11}
	move.l			DivSign,d6
	or.l			d6,d0

	; Done
	.Done:

endm
QuotientHi	dc.l	0
QuotientLo	dc.l	0
DivSign		dc.l	0
DivLead		dc.b	0
			even


;
;
;
FDIVHANDLER macro

	; Debug instruction
	WRITEDEBUG		#.DEBUGOP,INSTRUCTION

	; Increment PC
	INREMENTPC		#$04

	; Get data
	GETDATALENGTH	d0
	GETEAVALUE		d2,d3
	GETREGISTER		d5
	MOVEFPNTODN		d5,d0,d1

	; Emulate instruction
	FE_FDIV

	; Write results
	GETREGISTER		d5
	MOVEDNTOFPN		d5,d0,d1

	; Set condition codes
	SETCC			d0,d1

endm


;
; fdiv emulation
;
FdivHandler
FsdivHandler
FddivHandler
FsgldivHandler
	FDIVHANDLER
	rts

	; Debug constants
	.DEBUGOP:
	dc.b 			"fdiv %08lx",10,0
	even
const_025:	dc.l	$3fd00000,$0
