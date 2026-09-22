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
;
;
FMULHANDLER macro

	; Debug instruction
	WRITEDEBUG		#.DEBUGOP,INSTRUCTION

	; Increment PC
	INREMENTPC		#$04

	; Get data -- see fadd.asm's FADDHANDLER for why source is fetched
	; first, into d3/d4/d5.
	GETDATALENGTH	d0
    ifnb \1
        MOVEFROMC       010,3
        vperm           #$01230123,d3,d3,d2
	else
		GETEAVALUE		d3,d4,d5
	endif
	GETREGISTER		d6
	MOVEFPNTODN		d6,d0,d1,d2

	; Emulate instruction
	FE_FMUL

	; Write results
	GETREGISTER		d6
	MOVEDNTOFPN		d6,d0,d1,d2

	; Set condition codes
	SETCC			d0,d1,d2

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
