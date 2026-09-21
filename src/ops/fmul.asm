;
; d0 - destination high -> destination fraction high / result high
; d1 - destination low  -> result low
; d2 - source high -> source fraction high
; d3 - source low
; d4 - destination exponent -> combined result exponent
; d5 - source exponent -> scratch (MUL64) -> round bit
; d6 - scratch (MUL64) -> sticky flag
; d7 - reserved
;
FE_FMUL macro

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

	; Ordinary: compute the sign and go straight to the real multiply.
	move.l			d0,d6
	eor.l			d2,d6
	and.l			#$80000000,d6
	bra.w			.MainBody

	.SpecialCase:
	; Result sign = XOR of the operand signs (both are bit31 of d0/d2;
	; isolate just that bit so it can be OR'd straight into the result
	; later without needing FE_FADD's right-justified {0:1} convention).
	move.l			d0,d6
	eor.l			d2,d6
	and.l			#$80000000,d6

	; Check exponent for infinities and NaNs (kept as-is, matching
	; FE_FADD's pragmatic non-IEEE-complete passthrough -- true special
	; case handling beyond this fast path stays out of scope here too)
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

	; Check exponent for zeroes: unlike add, x*0 is always 0 (with the
	; XOR'd sign), never "the other operand".
	tst.w			d4
	bne.s			.DstExpNoZ
	moveq			#0,d0
	moveq			#0,d1
	or.l			d6,d0
	bra.w			.Done
	.DstExpNoZ:
	tst.w			d5
	bne.s			.SrcExpNoZ
	moveq			#0,d0
	moveq			#0,d1
	or.l			d6,d0
	bra.w			.Done
	.SrcExpNoZ:

	.MainBody:
	; Combined (biased) exponent, before any renormalization below
	add.w			d5,d4
	sub.w			#1023,d4

	; Extract fractions (hidden bit set explicitly, as everywhere else)
	bfextu			d0{12:20},d0
	bfextu			d2{12:20},d2
	bset			#20,d0
	bset			#20,d2

	; Multiply the two 53-bit mantissas -> 106-bit product in d0:d1:d2:d3.
	; Sign is safely stashed first since MUL64 needs d5/d6 as scratch.
	move.l			d6,MulSign
	MUL64			d0,d1,d2,d3,d5,d6
	move.l			d0,MulProduct
	move.l			d1,MulProduct+4
	move.l			d2,MulProduct+8
	move.l			d3,MulProduct+12

	; The product of two values in [2^52,2^53) lands in [2^104,2^106):
	; its leading bit is always at bit 104, and bit 105 besides that iff
	; the product is >= 2^105. Two fixed cases, so two fixed bitfield
	; offsets -- no need for a general variable-shift normalizer here.
	; Each extracts the top 53 significant bits (hidden bit landing at
	; bit 20 of d0, matching the usual convention) plus one more bit to
	; round on and a sticky flag summarizing everything below that.
	lea.l			MulProduct,a0
	btst			#9,d0
	beq.s			.Top104

	.Top105:
	addq.w			#1,d4
	bfextu			(a0){22:21},d0
	bfextu			(4,a0){11:32},d1
	bfextu			(8,a0){11:1},d5
	move.l			d2,d6
	andi.l			#$000fffff,d6
	or.l			d3,d6
	bra.s			.Round

	.Top104:
	bfextu			(a0){23:21},d0
	bfextu			(4,a0){12:32},d1
	bfextu			(8,a0){12:1},d5
	move.l			d2,d6
	andi.l			#$0007ffff,d6
	or.l			d3,d6

	; Round to nearest, ties to even: d5 = round bit, d6 = sticky (any
	; 1 bit below the round bit).
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
	move.l			MulSign,d6
	or.l			d6,d0

	; Done
	.Done:

endm
MulProduct	dc.l	0,0,0,0
MulSign		dc.l	0


;
;
;
FMULHANDLER macro

	; Debug instruction
	WRITEDEBUG		#.DEBUGOP,INSTRUCTION

	; Increment PC
	INREMENTPC		#$04

	; Get data
	GETDATALENGTH	d0
    ifnb \1
        MOVEFROMC       010,3
        vperm           #$01230123,d3,d3,d2
	else
		GETEAVALUE		d2,d3
	endif
	GETREGISTER		d5
	MOVEFPNTODN		d5,d0,d1

	; Emulate instruction
	FE_FMUL

	; Write results
	GETREGISTER		d5
	MOVEDNTOFPN		d5,d0,d1

	; Set condition codes
	SETCC			d0,d1

endm


;
; fmul emulation
;
FmulHandler
FsmulHandler
FdmulHandler
FsglmulHandler
	FMULHANDLER
	rts
	.DEBUGOP:
	dc.b 			"fmul %08lx",10,0
	even
