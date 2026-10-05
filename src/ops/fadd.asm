;
; Extended format (checklist #4: 15-bit exponent, explicit 64-bit
; mantissa in two full registers -- no more hidden-bit-at-bit-20 insert/
; strip). d0/d3 must stay untouched (original word0) through the whole
; special-case ladder, since the Inf/zero passthrough cases need to copy
; the OTHER operand's bits verbatim -- only .MainBody (reached once we
; know neither operand needs passthrough) repurposes d0/d3 into working
; sign+exponent registers. This is also why the fast path doesn't thread
; anything through to .MainBody itself: it just jumps there, and
; .MainBody re-reads d0/d3 fresh regardless of which path led to it.
;
; d0 - destination sign(1):exponent(15):reserved(16) -> working exponent
;      (sign at bit31, exponent right-justified low 15 bits) -> result
;      sign+exponent
; d1 - destination mantissa hi32 (explicit int bit at 31) -> result
; d2 - destination mantissa lo32 -> result
; d3 - source sign(1):exponent(15):reserved(16) -> working exponent, same
;      convention as d0
; d4 - source mantissa hi32 -> free after the add/subtract below, reused
;      as NORMALIZE's scratch
; d5 - source mantissa lo32
; d6 - scratch (fast-path probe, Inf/NaN/zero probe, sign-differs test,
;      result sign -- must survive to the final result-sign insert)
; d7 - reserved
;
FE_FADD macro

	; Fast path: both operands "ordinary" (finite, nonzero, not a
	; denormal -- exponent in [1,32766])? Read exponents non-
	; destructively (into scratch, not d0/d3) -- if either fails the
	; range check we fall into the special-case ladder below, which
	; needs d0/d3 intact.
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
	; Check exponent for infinities and NaNs
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

	; Check exponent for zeroes (bfextu sets Z/N on the extracted field
	; itself, same convention NORMALIZE's bfffo already relies on)
	bfextu			d0{1:15},d6
	bne.s			.DstExpNoZ
	move.l			d3,d0
	move.l			d4,d1
	move.l			d5,d2
	bra.w			.Done
	.DstExpNoZ:
	bfextu			d3{1:15},d6
	beq.w			.Done

	.MainBody:
	; Build working sign+exponent registers: sign stays at bit31,
	; exponent moves from bits30-16 to right-justified low 15 bits so
	; ALIGNEXPONENT/NORMALIZE's .w compares/adds see a plain value.
	bfextu			d0{0:1},d6
	bfextu			d0{1:15},d0
	bfins			d6,d0{0:1}
	bfextu			d3{0:1},d6
	bfextu			d3{1:15},d3
	bfins			d6,d3{0:1}

	; Align exponents (mantissas already explicit-bit -- no bset needed)
	ALIGNEXPONENT	d0,d1,d2,d3,d4,d5

	; Combine the (now equal-exponent) mantissas. This can NOT reuse the
	; old double-format version's NEG64+ADD64+ABS64 "convert both to
	; 2's complement, add, take the result's sign+magnitude" trick: that
	; trick needs a spare top bit to detect the add's own sign in, which
	; the old 53-bit mantissa had (stored in a 64-bit pair with 11 bits
	; of headroom) but a genuine 64-bit mantissa does not -- its top bit
	; is *always* set (the explicit integer bit), so ABS64's "negative if
	; bit 31 set" test fired on every call regardless of the true sign,
	; corrupting every add (found by hand-simulating this in Python
	; against a few golden vectors, since the wrong answers didn't
	; obviously point at this line). Same-sign and different-sign cases
	; are handled directly instead, below.
	move.l			d0,d6
	eor.l			d3,d6
	btst			#31,d6
	bne.w			.DiffSigns

	.SameSign:
	; Unsigned mantissa add. Aligned mantissas are each in [2^63,2^64)
	; or smaller (the smaller-exponent operand was already shifted
	; right by ALIGNEXPONENT), so this can carry past 64 bits but isn't
	; guaranteed to -- roll the carry (if any) back in as the new
	; explicit integer bit and bump the exponent to match.
	ADD64			d4,d5,d1,d2
	bcc.s			.SameSignNoCarry
	roxr.l			#1,d1
	roxr.l			#1,d2
	addq.w			#1,d0
	.SameSignNoCarry:
	move.l			d0,d6
	and.l			#$80000000,d6
	bra.w			.Combined

	.DiffSigns:
	; Compare the aligned mantissas directly and subtract the smaller
	; from the larger -- no 2's-complement round trip, so no spare bit
	; needed.
	cmp.l			d1,d4
	bhi.s			.SrcLarger
	blo.s			.DstLarger
	cmp.l			d2,d5
	bhi.s			.SrcLarger
	blo.s			.DstLarger

	; Exactly equal magnitudes, opposite signs: result is +0. Leave the
	; exponent as whatever ALIGNEXPONENT left it -- NORMALIZE's own
	; zero-mantissa case below zeroes it.
	moveq			#0,d1
	moveq			#0,d2
	moveq			#0,d6
	bra.w			.Combined

	.SrcLarger:
	SUB64			d1,d2,d4,d5
	move.l			d4,d1
	move.l			d5,d2
	move.l			d3,d6
	and.l			#$80000000,d6
	bra.s			.Combined

	.DstLarger:
	SUB64			d4,d5,d1,d2
	move.l			d0,d6
	and.l			#$80000000,d6

	.Combined:
	; Normalize (d4 free -- fully consumed by the add/subtract above)
	NORMALIZE		d0,d1,d2,d4

	; Construct result word0: move the (possibly NORMALIZE-adjusted)
	; exponent from its right-justified working position back to bits
	; 30-16 (the shift naturally discards the stale operand sign still
	; sitting in bit31, leaving bit31 clear), then OR in the real sign
	; computed above (d6, already 0 or $80000000 -- NOT bfins, which
	; would insert only d6's bit0: every sign-producing path above
	; builds d6 with "and.l #$80000000,d6", so its bit0 is always 0
	; regardless of the actual sign, and `bfins d6,d0{0:1}` silently
	; forced every result positive. Caught via a bench vector testing
	; fsub/FE_FADD with a negative result -- nothing in the existing
	; suite exercised MainBody's DiffSigns/SameSign paths with one).
	lsl.l			#8,d0
	lsl.l			#8,d0
	or.l			d6,d0

	; Done
	.Done:

endm


;
; Relaxed-precision internal format (checklist #12): effective 32-bit
; mantissa instead of the full 64-bit one FE_FADD above uses. Gated by
; MANTISSA32 -- a build-time choice (vasm -D MANTISSA32), never silently
; on; the default build is still full 64-bit ("science work" precision).
; Keeps #4's 80-bit (RegFpn) storage layout exactly as-is -- only the
; SIGNIFICANT width of the mantissa narrows, by rounding every operand
; down to 32 bits (round to nearest, ties to even) before combining, and
; forcing every result's low mantissa word (d2) to 0. That rounding runs
; on every operand on every call (not just once at some boundary), so
; this is correct regardless of what a value's low 32 mantissa bits
; already contain -- the same "round first" relaxation #5's single-
; precision fast path already uses (FE_FMUL_SINGLE/FE_FDIV_SINGLE in
; fmul.asm/fdiv.asm), just at a different width (32 instead of 24 bits)
; and applied to every fadd/fsub call under this build, not only ones
; FPCR/the opcode explicitly marks single. Verified in Python (the
; align/combine/normalize structure directly against FE_FADD's own
; 64-bit algorithm, operand rounding against exact Fraction arithmetic,
; 50000 random cases, 0 mismatches) before writing this.
;
; d0 - destination sign(1):exponent(15):reserved(16) -> working exponent
;      -> result sign+exponent
; d1 - destination mantissa hi32 -> rounded 32-bit dst mantissa -> result
;      mantissa (d2 is always written back 0 in this mode)
; d2 - destination mantissa lo32 -> round/sticky source for the dst
;      rounding step, then unused
; d3 - source sign(1):exponent(15):reserved(16) -> working exponent
; d4 - source mantissa hi32 -> rounded 32-bit src mantissa
; d5 - source mantissa lo32 -> round/sticky source for the src rounding
;      step, then unused
; d6 - scratch
; d7 - reserved
;
	ifd MANTISSA32
FE_FADD_32 macro

	; Fast path / special-case ladder -- identical to FE_FADD's, width-
	; independent (see there for the reasoning)
	bfextu			d0{1:15},d6
	subq.w			#1,d6
	cmp.w			#32766,d6
	bhs.s			.N32SpecialCase
	bfextu			d3{1:15},d6
	subq.w			#1,d6
	cmp.w			#32766,d6
	bhs.s			.N32SpecialCase
	bra.w			.N32MainBody

	.N32SpecialCase:
	bfextu			d0{1:15},d6
	cmp.w			#$7fff,d6
	bne.s			.N32DstExpOk
	bra.w			.N32Done
	.N32DstExpOk:
	bfextu			d3{1:15},d6
	cmp.w			#$7fff,d6
	bne.s			.N32SrcExpOk
	move.l			d3,d0
	move.l			d4,d1
	move.l			d5,d2
	bra.w			.N32Done
	.N32SrcExpOk:

	bfextu			d0{1:15},d6
	bne.s			.N32DstExpNoZ
	move.l			d3,d0
	move.l			d4,d1
	move.l			d5,d2
	bra.w			.N32Done
	.N32DstExpNoZ:
	bfextu			d3{1:15},d6
	beq.w			.N32Done

	.N32MainBody:
	; Build working sign+exponent registers -- see FE_FADD's MainBody
	bfextu			d0{0:1},d6
	bfextu			d0{1:15},d0
	bfins			d6,d0{0:1}
	bfextu			d3{0:1},d6
	bfextu			d3{1:15},d3
	bfins			d6,d3{0:1}

	; Round dst mantissa (d1:d2, 64 bits) down to a 32-bit value in d1:
	; d2 is already exactly what a 64->32 round needs as round+sticky
	; (bit31 = round bit, bits30-0 = sticky) with no shifting at all --
	; unlike FE_FMUL_SINGLE's 64->24 round, 32 lands exactly on a
	; register boundary.
	tst.l			d2
	beq.s			.N32DstNoRound
	btst			#31,d2
	beq.s			.N32DstNoRound
	move.l			d2,d6
	and.l			#$7fffffff,d6
	bne.s			.N32DstRoundUp
	btst			#0,d1
	beq.s			.N32DstNoRound
	.N32DstRoundUp:
	addq.l			#1,d1
	bcc.s			.N32DstNoRound
	; mantissa overflowed past 32 bits (was all-ones): renormalize
	move.l			#$80000000,d1
	addq.w			#1,d0
	.N32DstNoRound:

	; Same for the source mantissa (d4:d5 -> d4)
	tst.l			d5
	beq.s			.N32SrcNoRound
	btst			#31,d5
	beq.s			.N32SrcNoRound
	move.l			d5,d6
	and.l			#$7fffffff,d6
	bne.s			.N32SrcRoundUp
	btst			#0,d4
	beq.s			.N32SrcNoRound
	.N32SrcRoundUp:
	addq.l			#1,d4
	bcc.s			.N32SrcNoRound
	move.l			#$80000000,d4
	addq.w			#1,d3
	.N32SrcNoRound:

	; Align exponents -- single-register shift of whichever mantissa has
	; the smaller exponent (same roles as ALIGNEXPONENT's \1,\2,\4,\5,
	; just without a \3/\6 low word to carry along)
	cmp.w			d0,d3
	beq.s			.N32ExpOk
	bmi.s			.N32ExpNeg

	.N32ExpPos:
	; d3 (src exp) >= d0 (dst exp): shift the dst mantissa (d1) right
	sub.w			d0,d3
	add.w			d3,d0
	cmp.w			#32,d3
	blt.s			.N32ExpPosShift
	moveq			#0,d1
	bra.s			.N32ExpOk
	.N32ExpPosShift:
	lsr.l			d3,d1
	bra.s			.N32ExpOk

	.N32ExpNeg:
	; d3 (src exp) < d0 (dst exp): shift the src mantissa (d4) right
	sub.w			d0,d3
	neg.w			d3
	cmp.w			#32,d3
	blt.s			.N32ExpNegShift
	moveq			#0,d4
	bra.s			.N32ExpOk
	.N32ExpNegShift:
	lsr.l			d3,d4

	.N32ExpOk:
	move.w			d0,d3

	; Combine (mantissas already explicit-bit, no bset needed)
	move.l			d0,d6
	eor.l			d3,d6
	btst			#31,d6
	bne.w			.N32DiffSigns

	.N32SameSign:
	add.l			d4,d1
	bcc.s			.N32SameSignNoCarry
	roxr.l			#1,d1
	addq.w			#1,d0
	.N32SameSignNoCarry:
	move.l			d0,d6
	and.l			#$80000000,d6
	bra.w			.N32Combined

	.N32DiffSigns:
	cmp.l			d1,d4
	bhi.s			.N32SrcLarger
	blo.s			.N32DstLarger

	; Exactly equal magnitudes, opposite signs: result is +0
	moveq			#0,d1
	moveq			#0,d6
	bra.w			.N32Combined

	.N32SrcLarger:
	sub.l			d1,d4
	move.l			d4,d1
	move.l			d3,d6
	and.l			#$80000000,d6
	bra.s			.N32Combined

	.N32DstLarger:
	sub.l			d4,d1
	move.l			d0,d6
	and.l			#$80000000,d6

	.N32Combined:
	; Normalize -- single-word version of NORMALIZE: no LowNormalize
	; fallback (there's only one word), and no HighNormalizeRight branch
	; (NORMALIZE's own comment already notes that one's unreachable --
	; bfffo can't return negative, so it's dead code there too).
	bfffo			d1{0:32},d4
	bne.s			.N32HighNormalize

	move.w			#0,d0
	moveq			#0,d1
	bra.s			.N32NormalizeOk

	.N32HighNormalize:
	cmp.b			#0,d4
	beq.s			.N32NormalizeOk
	sub.w			d4,d0
	lsl.l			d4,d1

	.N32NormalizeOk:
	tst.w			d0
	bgt.s			.N32NoUnderflow
	move.w			#0,d0
	moveq			#0,d1
	.N32NoUnderflow:
	cmp.w			#32767,d0
	blt.s			.N32NoOverflow
	move.w			#$7fff,d0
	move.l			#$80000000,d1
	.N32NoOverflow:

	; Construct result word0 (see FE_FADD for why the shift alone is
	; enough), and force the low mantissa word flat per #12's contract
	moveq			#0,d2
	lsl.l			#8,d0
	lsl.l			#8,d0
	or.l			d6,d0

	.N32Done:

endm
	endif


;
;
;
FADDHANDLER macro

	; Debug instruction
	WRITEDEBUG		#.DEBUGOP,INSTRUCTION

	; Increment PC
	INREMENTPC		#$04

	; Get data. Source fetched first into d3/d4/d5 so it can't collide
	; with the destination's d0/d1/d2 (GETREGISTER uses d6 for the FPn
	; index rather than d5, which now holds part of the source operand).
	GETDATALENGTH	d0
    ifnb \1
		; TODO: use this with all ops, according to BigGun now all datatypes are being converted
		; NOTE: pre-existing, unreachable in current builds (no caller
		; passes \1) -- left as historical partial work.
        MOVEFROMC       010,3
        vperm           #$01230123,d3,d3,d2
	else
		GETEAVALUE		d3,d4,d5
	endif
	GETREGISTER		d6
	MOVEFPNTODN		d6,d0,d1,d2

	; Emulate instruction. Checklist #12: fadd has no FPCR-single check to
	; preserve (row 5 only covers fmul/fdiv -- see FMULHANDLER), so under
	; MANTISSA32 the narrowed path is simply the only path.
	ifd MANTISSA32
		FE_FADD_32
	else
		FE_FADD
	endif

	; Write results
	GETREGISTER		d6
	MOVEDNTOFPN		d6,d0,d1,d2

	; Set condition codes
	SETCC			d0,d1,d2

endm


;
; 
;
FaddHandler
FsaddHandler
FdaddHandler
	FADDHANDLER
	rts
	.DEBUGOP:
	dc.b 			"fadd %08lx",10,0
	even
