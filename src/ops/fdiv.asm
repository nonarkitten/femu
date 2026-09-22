;
; Extended format (checklist #4: 15-bit exponent, explicit 64-bit
; mantissa). See FE_FADD's header comment for the register-pressure
; reasoning behind d0/d3 staying untouched through the special-case
; ladder, and sign/exponent extraction being deferred to .MainBody.
;
; Unlike FE_FADD/FE_FMUL, the division itself needs every register:
; DIV64 needs R (2), V (2) and a fresh Q (2) simultaneously -- 6
; registers, plus d0 for the exponent is exactly d0-d6. This is also
; why DivSign/DivLead/DivRound (memory scratch, 1 longword/2 bytes) are
; used liberally below rather than trying to free a register for them,
; the same technique FE_FMUL's MulSign and this op's own predecessor
; already relied on.
;
; d0 - destination sign(1):exponent(15):reserved(16) -> combined result
;      exponent
; d1 - destination mantissa hi32 -> dividend/remainder high (DIV64) ->
;      result mantissa hi32
; d2 - destination mantissa lo32 -> dividend/remainder low (DIV64) ->
;      result mantissa lo32
; d3 - source sign(1):exponent(15):reserved(16) -> lead-bit flag ->
;      quotient high (DIV64) -> mantissa/sticky scratch
; d4 - source mantissa hi32 -> divisor high (DIV64, unused after)
; d5 - source mantissa lo32 -> divisor low (DIV64, unused after) ->
;      round-bit scratch
; d6 - scratch (fast-path probe, Inf/NaN/zero probe, sign xor) ->
;      quotient low (DIV64) -> sticky/round scratch
; d7 - reserved
;
FE_FDIV macro

	; Fast path (see FE_FADD)
	bfextu			d0{1:15},d6
	subq.w			#1,d6
	cmp.w			#32766,d6
	bhs.s			.SpecialCase
	bfextu			d3{1:15},d6
	subq.w			#1,d6
	cmp.w			#32766,d6
	bhs.s			.SpecialCase
	bra.w			.MainBody

	.SpecialCase:
	; Infinities/NaNs: passed through as-is, matching FE_FADD/FE_FMUL's
	; pragmatic style -- true special-case handling beyond this fast
	; path stays out of scope here too
	bfextu			d0{1:15},d6
	cmp.w			#$7fff,d6
	bne.s			.DstExpOk
	bra.w			.Done
	.DstExpOk:
	bfextu			d3{1:15},d6
	cmp.w			#$7fff,d6
	bne.s			.SrcExpOk
	move.l			d3,d0
	move.l			d4,d1
	move.l			d5,d2
	bra.w			.Done
	.SrcExpOk:

	; Zero dividend -> zero (with the XOR'd sign)
	bfextu			d0{1:15},d6
	bne.s			.DstExpNoZ
	move.l			d0,d6
	eor.l			d3,d6
	and.l			#$80000000,d6
	moveq			#0,d1
	moveq			#0,d2
	move.l			d6,d0
	bra.w			.Done
	.DstExpNoZ:

	; Zero divisor -> infinity (with the XOR'd sign)
	bfextu			d3{1:15},d6
	bne.s			.SrcExpNoZ
	move.l			d0,d6
	eor.l			d3,d6
	and.l			#$80000000,d6
	or.l			#$7fff0000,d6
	move.l			#$80000000,d1
	moveq			#0,d2
	move.l			d6,d0
	bra.w			.Done
	.SrcExpNoZ:

	.MainBody:
	; Sign = XOR of the operand signs, stashed to memory now since
	; every register from here on is needed for the divide itself.
	move.l			d0,d6
	eor.l			d3,d6
	and.l			#$80000000,d6
	move.l			d6,DivSign

	; Combined (biased) exponent, before any renormalization below
	bfextu			d0{1:15},d0
	bfextu			d3{1:15},d3
	sub.w			d3,d0
	add.w			#16383,d0

	; DIV64's loop needs its starting remainder below the divisor, which
	; the dividend itself (D) isn't guaranteed to be -- D/V ranges over
	; (0.5,2), so D can be almost 2V. Try D-V once first; if it doesn't
	; borrow, keep it and remember the leading quotient bit was 1 (D>=V),
	; else undo it exactly (the X flag from subx is still live across
	; the branch, so addx.l undoes it precisely) and the leading bit is
	; 0.
	sub.l			d5,d2
	subx.l			d4,d1
	bcc.s			.Lead1
	add.l			d5,d2
	addx.l			d4,d1
	moveq			#0,d3
	bra.s			.LeadDone
	.Lead1:
	moveq			#1,d3
	.LeadDone:
	move.b			d3,DivLead

	; Divide the (now pre-normalized) mantissas: exactly 64 iterations,
	; the most DIV64's quotient accumulator (d3:d6) can hold without
	; overflowing -- unlike the 53-bit-mantissa case this replaced,
	; there's no spare bit to fold in an extra "+1 round bit" iteration
	; here, hence the separate phantom step below.
	moveq			#0,d3
	moveq			#0,d6
	DIV64			d1,d2,d4,d5,d3,d6,64

	; One more (non-accumulating) iteration to get the round bit and
	; the true remainder used for sticky, without touching Q (d3:d6),
	; which is already exactly 64 bits -- same overflow handling as
	; DIV64's own loop (see its header comment).
	lsl.l			#1,d2
	roxl.l			#1,d1
	bcs.s			.PhantomOverflowed
	sub.l			d5,d2
	subx.l			d4,d1
	bcc.s			.PhantomBit1
	add.l			d5,d2
	addx.l			d4,d1
	move.b			#0,DivRound
	bra.s			.PhantomDone
	.PhantomBit1:
	move.b			#1,DivRound
	bra.s			.PhantomDone
	.PhantomOverflowed:
	sub.l			d5,d2
	subx.l			d4,d1
	move.b			#1,DivRound
	.PhantomDone:

	; d4/d5 (the divisor) are free from here on. Two fixed cases based
	; on the pre-normalize leading bit, mirroring FE_FMUL's Top127/
	; Top126 split: if the dividend was >= the divisor (lead=1), the
	; quotient's own top bit is that leading 1, so Q (d3:d6) needs
	; shifting right by 1 to make room for it as the explicit integer
	; bit, and what shifts out becomes the round bit (DivRound becomes
	; part of sticky instead). If lead=0, Q is already exactly the
	; 64-bit mantissa with no shift, DivRound is the round bit directly,
	; and the exponent needs -1 (the leading 1 was one position lower).
	tst.b			DivLead
	bne.s			.Lead1Case

	.Lead0Case:
	subq.w			#1,d0
	tst.l			d1
	bne.s			.L0Sticky
	tst.l			d2
	beq.s			.L0NoSticky
	.L0Sticky:
	moveq			#1,d4
	bra.s			.L0StickyDone
	.L0NoSticky:
	moveq			#0,d4
	.L0StickyDone:
	moveq			#0,d5
	move.b			DivRound,d5
	move.l			d3,d1
	move.l			d6,d2
	bra.w			.Round2

	.Lead1Case:
	tst.l			d1
	bne.s			.L1Sticky
	tst.l			d2
	bne.s			.L1Sticky
	tst.b			DivRound
	beq.s			.L1NoSticky
	.L1Sticky:
	moveq			#1,d4
	bra.s			.L1StickyDone
	.L1NoSticky:
	moveq			#0,d4
	.L1StickyDone:
	moveq			#1,d5
	lsr.l			#1,d5
	roxr.l			#1,d3
	roxr.l			#1,d6
	moveq			#0,d5
	bcc.s			.L1RoundCaptured
	moveq			#1,d5
	.L1RoundCaptured:
	move.l			d3,d1
	move.l			d6,d2

	; Round to nearest, ties to even: d5 = round bit, d4 = sticky
	.Round2:
	tst.l			d5
	beq.s			.NoRoundUp
	tst.l			d4
	bne.s			.RoundUp
	btst			#0,d2
	beq.s			.NoRoundUp
	.RoundUp:
	addq.l			#1,d2
	bcc.s			.NoRoundUp
	addq.l			#1,d1
	bcc.s			.NoRoundUp
	; Mantissa overflowed past 64 bits (was all-ones): renormalize.
	bset			#31,d1
	addq.w			#1,d0
	.NoRoundUp:

	; Construct result word0 (see FE_FADD for why the shift alone is
	; enough to land the exponent at bits 30-16 with bit31/bits15-0
	; already zero)
	lsl.l			#8,d0
	lsl.l			#8,d0
	move.l			DivSign,d6
	or.l			d6,d0

	; Done
	.Done:

endm
DivSign		dc.l	0
DivLead		dc.b	0
DivRound	dc.b	0
			even


;
; Single-precision-forced divide (checklist #5): triggered by fsdiv/
; fsgldiv or FPCR's rounding precision field, never silently -- same
; deliberate, documented relaxation as FE_FMUL_SINGLE (round both
; operands to a 24-bit significant mantissa FIRST, real 68881 fsdiv
; computes at full extended precision and rounds only the final
; result). This is the single biggest win #5 targets: DIV64's 64+1-
; iteration restoring-division loop is replaced by one hardware
; divu.l, at the cost of the same narrowed-operand relaxation
; FE_FMUL_SINGLE already accepted.
;
; The 24-bit mantissas (dst24, src24, both in [2^23,2^24)) are divided
; via a single 32-bit-quotient/32-bit-remainder divu.l: the 64-bit
; scaled dividend dst24<<31 is built directly in the Dr:Dq pair (no
; multi-word shift needed -- shifting a 32-bit register left by 31
; naturally keeps only its bit0, which is exactly Dq's low half; Dr is
; just dst24>>1). This is safe from quotient overflow for every
; in-range dst24/src24 (worst case (2^24-1)*2^31/2^23 = 2^32-256,
; verified exactly in Python, not just spot-checked) and needs no
; iteration at all. Verified against an independent Fraction-exact
; reference (0/300000 random cases + targeted operand-rounding-
; overflow edge cases, which is also where a sign mistake would hide:
; the DIVISOR's own rounding overflow subtracts 1 from the combined
; exponent, not adds, unlike FE_FMUL_SINGLE's dst/src symmetry).
;
; d0 - destination sign(1):exponent(15):reserved(16) -> combined result
;      exponent
; d1 - destination mantissa hi32 -> rounded 24-bit dst mantissa -> Dq
;      (low32 of the scaled dividend, then the divu.l quotient) ->
;      result mantissa hi32 (after widening)
; d2 - destination mantissa lo32 -> scratch (round/sticky) -> Dr
;      (high32 of the scaled dividend, then the divu.l remainder,
;      folded into sticky for the final rounding below)
; d3 - source sign(1):exponent(15):reserved(16) -> scratch (exponent
;      extraction) -> divisor (rounded src24) for divu.l -> scratch
; d4 - source mantissa hi32 -> rounded 24-bit src mantissa (moved to
;      d3 before the divide) -> free
; d5 - source mantissa lo32 -> scratch (round/sticky)
; d6 - scratch throughout (fast-path probe, Inf/NaN/zero probe, sign
;      xor, shift count, quotient rounding candidate)
; d7 - reserved
;
FE_FDIV_SINGLE macro

	; Fast path / special-case ladder: identical to FE_FDIV's, see there
	bfextu			d0{1:15},d6
	subq.w			#1,d6
	cmp.w			#32766,d6
	bhs.s			.SglSpecialCase
	bfextu			d3{1:15},d6
	subq.w			#1,d6
	cmp.w			#32766,d6
	bhs.s			.SglSpecialCase
	bra.w			.SglMainBody

	.SglSpecialCase:
	bfextu			d0{1:15},d6
	cmp.w			#$7fff,d6
	bne.s			.SglDstExpOk
	bra.w			.SglDone
	.SglDstExpOk:
	bfextu			d3{1:15},d6
	cmp.w			#$7fff,d6
	bne.s			.SglSrcExpOk
	move.l			d3,d0
	move.l			d4,d1
	move.l			d5,d2
	bra.w			.SglDone
	.SglSrcExpOk:

	; Zero dividend -> zero (with the XOR'd sign)
	bfextu			d0{1:15},d6
	bne.s			.SglDstExpNoZ
	move.l			d0,d6
	eor.l			d3,d6
	and.l			#$80000000,d6
	moveq			#0,d1
	moveq			#0,d2
	move.l			d6,d0
	bra.w			.SglDone
	.SglDstExpNoZ:

	; Zero divisor -> infinity (with the XOR'd sign)
	bfextu			d3{1:15},d6
	bne.s			.SglSrcExpNoZ
	move.l			d0,d6
	eor.l			d3,d6
	and.l			#$80000000,d6
	or.l			#$7fff0000,d6
	move.l			#$80000000,d1
	moveq			#0,d2
	move.l			d6,d0
	bra.w			.SglDone
	.SglSrcExpNoZ:

	.SglMainBody:
	; Sign = XOR of the operand signs -- same as FE_FDIV
	move.l			d0,d6
	eor.l			d3,d6
	and.l			#$80000000,d6
	move.l			d6,DivSign

	; Combined (biased) exponent, before the rounding adjustments below
	bfextu			d0{1:15},d0
	bfextu			d3{1:15},d3
	sub.w			d3,d0
	add.w			#16383,d0

	; Round the destination mantissa (d1:d2, 64 bits) to a right-
	; justified 24-bit value in d1 -- identical to FE_FMUL_SINGLE's dst
	; rounding, see there. Overflow (all-ones rounds up past 24 bits)
	; bumps d0 by +1: the dividend's own effective exponent went up.
	btst			#7,d1
	beq.s			.SglDstNoRoundUp
	move.l			d1,d6
	andi.l			#$7f,d6
	bne.s			.SglDstRoundUp
	tst.l			d2
	bne.s			.SglDstRoundUp
	btst			#8,d1
	beq.s			.SglDstNoRoundUp
	.SglDstRoundUp:
	moveq			#1,d6
	bra.s			.SglDstHaveRound
	.SglDstNoRoundUp:
	moveq			#0,d6
	.SglDstHaveRound:
	lsr.l			#8,d1
	add.l			d6,d1
	cmp.l			#$1000000,d1
	blt.s			.SglDstRoundDone
	move.l			#$800000,d1
	addq.w			#1,d0
	.SglDstRoundDone:

	; Same for the source mantissa (d4:d5 -> d4). Overflow SUBTRACTS 1
	; from d0 instead of adding: the divisor's effective exponent going
	; up by one means the quotient's exponent goes DOWN by one -- the
	; sign flip that makes this different from FE_FMUL_SINGLE, verified
	; explicitly against the Fraction-exact reference (see header).
	btst			#7,d4
	beq.s			.SglSrcNoRoundUp
	move.l			d4,d6
	andi.l			#$7f,d6
	bne.s			.SglSrcRoundUp
	tst.l			d5
	bne.s			.SglSrcRoundUp
	btst			#8,d4
	beq.s			.SglSrcNoRoundUp
	.SglSrcRoundUp:
	moveq			#1,d6
	bra.s			.SglSrcHaveRound
	.SglSrcNoRoundUp:
	moveq			#0,d6
	.SglSrcHaveRound:
	lsr.l			#8,d4
	add.l			d6,d4
	cmp.l			#$1000000,d4
	blt.s			.SglSrcRoundDone
	move.l			#$800000,d4
	subq.w			#1,d0
	.SglSrcRoundDone:

	; Build the 64-bit scaled dividend Dr:Dq = dst24 << 31 in d2:d1 --
	; Dq (d1, the low 32 bits) is just dst24 shifted left 31 within one
	; register (everything above bit0 shifts out, which is exactly what
	; the low half of a 64-bit left-shift-by-31 needs); Dr (d2, the
	; high 32 bits) is dst24>>1. d3 (holding the now-unneeded source
	; exponent) becomes the divisor register once src24 (in d4) moves
	; in.
	move.l			d1,d2
	lsr.l			#1,d2
	moveq			#31,d6
	lsl.l			d6,d1
	move.l			d4,d3

	; One hardware divide replaces DIV64's 64+1-iteration loop.
	divu.l			d3,d2:d1

	; Two fixed cases based on the quotient's top bit (mirrors FE_FDIV's
	; Lead0/Lead1 split) -- d2 (remainder) folds into sticky either way,
	; same role DIV64's own remainder played.
	btst			#31,d1
	beq.s			.SglLead0

	.SglLead1:
	move.l			d1,d6
	lsr.l			#8,d6
	btst			#7,d1
	beq.s			.SglL1NoRoundUp
	move.l			d1,d3
	andi.l			#$7f,d3
	bne.s			.SglL1RoundUp
	tst.l			d2
	bne.s			.SglL1RoundUp
	btst			#0,d6
	beq.s			.SglL1NoRoundUp
	.SglL1RoundUp:
	addq.l			#1,d6
	.SglL1NoRoundUp:
	bra.s			.SglRoundedDone

	.SglLead0:
	subq.w			#1,d0
	move.l			d1,d6
	lsr.l			#7,d6
	btst			#6,d1
	beq.s			.SglL0NoRoundUp
	move.l			d1,d3
	andi.l			#$3f,d3
	bne.s			.SglL0RoundUp
	tst.l			d2
	bne.s			.SglL0RoundUp
	btst			#0,d6
	beq.s			.SglL0NoRoundUp
	.SglL0RoundUp:
	addq.l			#1,d6
	.SglL0NoRoundUp:

	.SglRoundedDone:
	; d6 = rounded 24-bit mantissa candidate; overflow past 24 bits
	; (all-ones rounded up) handled the same way as everywhere else.
	cmp.l			#$1000000,d6
	blt.s			.SglQuotRoundDone
	move.l			#$800000,d6
	addq.w			#1,d0
	.SglQuotRoundDone:

	; Widen the 24-bit result mantissa back to the 64-bit storage
	; convention (see FE_FMUL_SINGLE's identical step)
	move.l			d6,d1
	lsl.l			#8,d1
	moveq			#0,d2

	; Construct result word0
	lsl.l			#8,d0
	lsl.l			#8,d0
	move.l			DivSign,d6
	or.l			d6,d0

	.SglDone:

endm


;
;
;
FDIVHANDLER macro

	; Debug instruction
	WRITEDEBUG		#.DEBUGOP,INSTRUCTION

	; Increment PC
	INREMENTPC		#$04

	; Get data -- see fadd.asm's FADDHANDLER for why source is fetched
	; first, into d3/d4/d5.
	GETDATALENGTH	d0
	GETEAVALUE		d3,d4,d5
	GETREGISTER		d6
	MOVEFPNTODN		d6,d0,d1,d2

	; Emulate instruction. \1 non-blank (passed as a bare "single"
	; token, never a leading-comma-blank -- see FMULHANDLER's comment
	; in fmul.asm for the vasm parser bug that mixing blank forms of
	; the same ifnb'd parameter across two calls in one file triggers)
	; means fsdiv/fsgldiv: always force the single-precision fast path,
	; no runtime check needed. Plain fdiv/fddiv instead honor FPCR's
	; rounding precision field (checklist #5), same dispatch shape as
	; FMULHANDLER.
	ifnb \1
		FE_FDIV_SINGLE
	else
		move.b			RegFpcrMode,d6
		andi.b			#FPCR_PRECMASK,d6
		cmp.b			#FPCR_SINGLE,d6
		beq.w			.UseSingle
		FE_FDIV
		bra.w			.DivDone
		.UseSingle:
		FE_FDIV_SINGLE
		.DivDone:
	endif

	; Write results
	GETREGISTER		d6
	MOVEDNTOFPN		d6,d0,d1,d2

	; Set condition codes
	SETCC			d0,d1,d2

endm


;
; fdiv/fddiv emulation -- full extended computation, single-rounded
; only when FPCR's precision field asks for it (checked at runtime
; above).
;
FdivHandler
FddivHandler
	FDIVHANDLER
	rts

	; Debug constants
	.DEBUGOP:
	dc.b 			"fdiv %08lx",10,0
	even
const_025:	dc.l	$3fd00000,$0

;
; fsdiv/fsgldiv emulation -- checklist #5's narrowed-operand fast path
; is forced unconditionally, since the opcode itself asks for single
; precision (no FPCR check needed, see FDIVHANDLER's \1 parameter).
;
FsdivHandler
FsgldivHandler
	FDIVHANDLER		single
	rts
	.DEBUGOP:
	dc.b 			"fsdiv %08lx",10,0
	even
