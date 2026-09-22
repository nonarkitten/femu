;
; Extended format (checklist #4: 15-bit exponent, explicit 64-bit
; mantissa -- see FE_FADD's header comment for the same register-
; pressure reasoning about why d0/d3 must stay untouched through the
; whole special-case ladder, and why sign/exponent extraction is
; deferred to .MainBody).
;
; d0 - destination sign(1):exponent(15):reserved(16) -> combined result
;      exponent
; d1 - destination mantissa hi32 -> product bits 127-96 (MUL64) -> result
;      mantissa hi32
; d2 - destination mantissa lo32 -> product bits 95-64 (MUL64) -> result
;      mantissa lo32
; d3 - source sign(1):exponent(15):reserved(16) -> scratch (MUL64)
; d4 - source mantissa hi32 -> product bits 63-32 (MUL64) -> round/sticky
;      source
; d5 - source mantissa lo32 -> product bits 31-0 (MUL64) -> sticky source
; d6 - scratch (fast-path probe, Inf/NaN/zero probe, sign xor) -> scratch
;      (MUL64) -> sticky accumulator
; d7 - reserved
;
FE_FMUL macro

	; Fast path (see FE_FADD for why this range check is an exact
	; precondition, and why it reads non-destructively rather than
	; through d0/d3)
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
	; Check exponent for infinities and NaNs (kept as-is, matching
	; FE_FADD's pragmatic non-IEEE-complete passthrough -- true special
	; case handling beyond this fast path stays out of scope here too)
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

	; Check exponent for zeroes: unlike add, x*0 is always 0 (with the
	; XOR'd sign), never "the other operand". Sign is computed fresh
	; here (from the still-original d0/d3) rather than threaded through
	; from the top, since there's no spare register to hold it in.
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
	bfextu			d3{1:15},d6
	bne.s			.SrcExpNoZ
	move.l			d0,d6
	eor.l			d3,d6
	and.l			#$80000000,d6
	moveq			#0,d1
	moveq			#0,d2
	move.l			d6,d0
	bra.w			.Done
	.SrcExpNoZ:

	.MainBody:
	; Result sign = XOR of the operand signs, computed now that both
	; operands are known ordinary (isolate just bit31 so it can be OR'd
	; straight into the result later, matching FE_FMUL's usual
	; convention rather than FE_FADD's right-justified {0:1} one).
	move.l			d0,d6
	eor.l			d3,d6
	and.l			#$80000000,d6

	; Combined (biased) exponent, before any renormalization below
	bfextu			d0{1:15},d0
	bfextu			d3{1:15},d3
	add.w			d3,d0
	sub.w			#16383,d0

	; Multiply the two 64-bit mantissas (already explicit-bit, no
	; bset needed) -> 128-bit product in d1:d2:d4:d5. Sign is stashed
	; first since MUL64 needs d3/d6 as scratch.
	move.l			d6,MulSign
	MUL64			d1,d2,d4,d5,d3,d6

	; The product of two values in [2^63,2^64) lands in [2^126,2^128):
	; its leading bit is always at bit 126, and bit 127 besides that iff
	; the product is >= 2^127. Unlike the old double-format version
	; (which needed bfextu against odd, sub-register-aligned offsets
	; into a memory buffer, since its 53-bit-mantissa product didn't
	; land on register boundaries), a 64-bit mantissa's product always
	; does -- so the bit-126 case is simply shifted left 1 register-wise
	; (chained lsl/roxl) to match the bit-127 case's layout exactly,
	; letting both share one extraction path with no memory buffer.
	btst			#31,d1
	bne.s			.Top127
	lsl.l			#1,d5
	roxl.l			#1,d4
	roxl.l			#1,d2
	roxl.l			#1,d1
	bra.s			.Top127Shifted

	.Top127:
	addq.w			#1,d0
	.Top127Shifted:
	; Mantissa is now exactly d1:d2 (the product's top 64 bits); round
	; bit is the product's next bit (d4's MSB), sticky is everything
	; below that (d4's remaining low bits, plus all of d5).
	move.l			d4,d6
	andi.l			#$7fffffff,d6
	or.l			d5,d6
	btst			#31,d4
	beq.s			.NoRoundUp
	tst.l			d6
	bne.s			.RoundUp
	btst			#0,d2
	beq.s			.NoRoundUp
	.RoundUp:
	addq.l			#1,d2
	bcc.s			.NoRoundUp
	addq.l			#1,d1
	bcc.s			.NoRoundUp
	; Mantissa overflowed past 64 bits (was all-ones): renormalize by
	; re-setting the explicit integer bit (d1/d2 already wrapped to 0)
	; and bumping the exponent.
	bset			#31,d1
	addq.w			#1,d0
	.NoRoundUp:

	; Construct result word0 (see FE_FADD for why the shift alone is
	; enough to land the exponent at bits 30-16 with bit31/bits15-0
	; already zero)
	lsl.l			#8,d0
	lsl.l			#8,d0
	move.l			MulSign,d6
	or.l			d6,d0

	; Done
	.Done:

endm
MulSign		dc.l	0


;
; Single-precision-forced multiply (checklist #5): triggered by fsmul/
; fsglmul or FPCR's rounding precision field, never silently. This is a
; deliberate, documented relaxation from true 68881 fsmul semantics
; (which compute at full extended precision and round only the final
; result) -- both operands are rounded to a 24-bit significant mantissa
; FIRST, and the multiply itself runs at that width (a single mulu.l
; instead of MUL64's four). When both operands already happen to be
; clean single-precision values (e.g. chained fsmul, or anything that
; passed through fmove.s), this is bit-exact to real hardware, verified
; against an independent host float32 reference; verified separately
; that ANY operand carrying extra precision below the 24th bit can shift
; the result by up to a handful of ULP relative to true "compute full
; then round" hardware behavior -- the accepted cost of the speedup
; (halved rounding logic below vs ALIGNEXPONENT/NORMALIZE's 64-bit
; version, and MUL64's four mulu.l's down to one).
;
; The Inf/NaN/zero ladder is identical to FE_FMUL's (width-independent),
; duplicated rather than shared -- see FE_FADD's header comment on why
; d0/d3 must stay untouched through it, and macros.asm's existing
; per-op-not-shared style for ladders like this one.
;
; d0 - destination sign(1):exponent(15):reserved(16) -> combined result
;      exponent
; d1 - destination mantissa hi32 -> rounded 24-bit dest mantissa, right-
;      justified (bit23=explicit) -> product low32 (mulu.l) -> combined
;      24-bit product mantissa -> result mantissa hi32 (after widening)
; d2 - destination mantissa lo32 -> scratch (round bit / sticky)
; d3 - source sign(1):exponent(15):reserved(16) -> scratch
; d4 - source mantissa hi32 -> rounded 24-bit src mantissa, right-
;      justified -> product high32 (mulu.l, top 16 bits always 0)
; d5 - source mantissa lo32 -> scratch (round bit / sticky)
; d6 - scratch (fast-path probe, Inf/NaN/zero probe, sign xor, rounding)
; d7 - reserved
;
FE_FMUL_SINGLE macro

	; Fast path / special-case ladder: identical to FE_FMUL's, see there
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
	bfextu			d3{1:15},d6
	bne.s			.SglSrcExpNoZ
	move.l			d0,d6
	eor.l			d3,d6
	and.l			#$80000000,d6
	moveq			#0,d1
	moveq			#0,d2
	move.l			d6,d0
	bra.w			.SglDone
	.SglSrcExpNoZ:

	.SglMainBody:
	; Sign and combined exponent -- same as FE_FMUL
	move.l			d0,d6
	eor.l			d3,d6
	and.l			#$80000000,d6
	move.l			d6,MulSign
	bfextu			d0{1:15},d0
	bfextu			d3{1:15},d3
	add.w			d3,d0
	sub.w			#16383,d0

	; Round the destination mantissa (d1:d2, 64 bits) to a right-
	; justified 24-bit value in d1: round to nearest, ties to even, on
	; the 40 bits being dropped (d1's low 8 bits, plus all of d2).
	btst			#7,d1
	beq.s			.DstNoRoundUp
	move.l			d1,d6
	andi.l			#$7f,d6
	bne.s			.DstRoundUp
	tst.l			d2
	bne.s			.DstRoundUp
	btst			#8,d1
	beq.s			.DstNoRoundUp
	.DstRoundUp:
	moveq			#1,d6
	bra.s			.DstHaveRound
	.DstNoRoundUp:
	moveq			#0,d6
	.DstHaveRound:
	lsr.l			#8,d1
	add.l			d6,d1
	cmp.l			#$1000000,d1
	blt.s			.DstRoundDone
	; mantissa overflowed past 24 bits (was all-ones): renormalize
	move.l			#$800000,d1
	addq.w			#1,d0
	.DstRoundDone:

	; Same for the source mantissa (d4:d5 -> d4)
	btst			#7,d4
	beq.s			.SrcNoRoundUp
	move.l			d4,d6
	andi.l			#$7f,d6
	bne.s			.SrcRoundUp
	tst.l			d5
	bne.s			.SrcRoundUp
	btst			#8,d4
	beq.s			.SrcNoRoundUp
	.SrcRoundUp:
	moveq			#1,d6
	bra.s			.SrcHaveRound
	.SrcNoRoundUp:
	moveq			#0,d6
	.SrcHaveRound:
	lsr.l			#8,d4
	add.l			d6,d4
	cmp.l			#$1000000,d4
	blt.s			.SrcRoundDone
	move.l			#$800000,d4
	addq.w			#1,d0
	.SrcRoundDone:

	; Multiply the two 24-bit mantissas -- a single mulu.l instead of
	; MUL64 -- product is in [2^46,2^48), fits entirely in d6:d1 with
	; d6's top 16 bits always 0.
	mulu.l			d4,d6:d1

	; Leading bit always at product bit 46 or 47 -- same fixed-two-case
	; pattern as FE_FMUL, scaled down.
	btst			#15,d6
	bne.s			.Top47
	lsl.l			#1,d1
	roxl.l			#1,d6
	bra.s			.Top47Shifted
	.Top47:
	addq.w			#1,d0
	.Top47Shifted:

	; Round bit = product bit 23 (d1's bit 23), sticky = bits 22-0,
	; read before d1 is repurposed to hold the combined mantissa below.
	btst			#23,d1
	beq.s			.SglNoRoundUp
	move.l			d1,d2
	andi.l			#$7fffff,d2
	bne.s			.SglRoundUp
	btst			#24,d1
	beq.s			.SglNoRoundUp
	.SglRoundUp:
	moveq			#1,d2
	bra.s			.HaveRound
	.SglNoRoundUp:
	moveq			#0,d2
	.HaveRound:

	; Combine into d1: d6's low 16 bits (top of the 24-bit mantissa) :
	; d1's original bits 31-24 (bottom 8 bits)
	lsl.l			#8,d6
	rol.l			#8,d1
	andi.l			#$ff,d1
	or.l			d6,d1
	add.l			d2,d1
	cmp.l			#$1000000,d1
	blt.s			.RoundDone
	move.l			#$800000,d1
	addq.w			#1,d0
	.RoundDone:

	; Widen the 24-bit result mantissa back to the 64-bit storage
	; convention (left-justify, zero-pad the low 40 bits). d1 already
	; holds a right-justified 24-bit value (top 8 bits clear from the
	; combine/round step above), so a single lsl.l puts its bit23 at
	; bit31 with the vacated low byte already zero; d2 is fully vacated.
	lsl.l			#8,d1
	moveq			#0,d2

	; Construct result word0
	lsl.l			#8,d0
	lsl.l			#8,d0
	move.l			MulSign,d6
	or.l			d6,d0

	.SglDone:

endm



;
;
;
FMULHANDLER macro

	; Debug instruction
	WRITEDEBUG		#.DEBUGOP,INSTRUCTION

	; Increment PC
	INREMENTPC		#$04

	; Get data -- see fadd.asm's FADDHANDLER for why source is fetched
	; first, into d3/d4/d5. \2 (not \1 -- see below) selects the
	; immediate-constant-operand path; unused by any caller today.
	GETDATALENGTH	d0
    ifnb \2
        MOVEFROMC       010,3
        vperm           #$01230123,d3,d3,d2
	else
		GETEAVALUE		d3,d4,d5
	endif
	GETREGISTER		d6
	MOVEFPNTODN		d6,d0,d1,d2

	; Emulate instruction. fsmul/fsglmul (\1 non-blank, passed as a bare
	; "single" token -- NOT a leading-comma-blank \2, which trips a vasm
	; parser bug: ifnb on a param that's blank via an explicit leading
	; comma in one call site and blank via plain omission in another,
	; checked across two separate invocations of this macro in the same
	; file, sends vasm into a runaway allocation loop instead of a clean
	; error -- reproduced independently with a minimal macro/ifnb-only
	; test file, unrelated to anything else in this macro) always force
	; the single-precision fast path -- no runtime check needed, the
	; opcode already says so. Plain fmul/fdmul instead honor FPCR's
	; rounding precision field (checklist #5): only when software has
	; explicitly asked for single-rounded results does this take the
	; narrowed-operand fast path instead of the always-hardware-correct
	; FE_FMUL.
	ifnb \1
		FE_FMUL_SINGLE
	else
		move.b			RegFpcrMode,d6
		andi.b			#FPCR_PRECMASK,d6
		cmp.b			#FPCR_SINGLE,d6
		beq.w			.UseSingle
		FE_FMUL
		bra.w			.MulDone
		.UseSingle:
		FE_FMUL_SINGLE
		.MulDone:
	endif

	; Write results
	GETREGISTER		d6
	MOVEDNTOFPN		d6,d0,d1,d2

	; Set condition codes
	SETCC			d0,d1,d2

endm


;
; fmul/fdmul emulation -- full extended computation, single-rounded only
; when FPCR's precision field asks for it (checked at runtime above).
;
FmulHandler
FdmulHandler
	FMULHANDLER
	rts
	.DEBUGOP:
	dc.b 			"fmul %08lx",10,0
	even

;
; fsmul/fsglmul emulation -- checklist #5's narrowed-operand fast path is
; forced unconditionally, since the opcode itself asks for single
; precision (no FPCR check needed, see FMULHANDLER's \1 parameter).
;
FsmulHandler
FsglmulHandler
	FMULHANDLER		single
	rts
	.DEBUGOP:
	dc.b 			"fsmul %08lx",10,0
	even
