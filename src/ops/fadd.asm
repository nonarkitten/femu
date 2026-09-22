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
	; sitting in bit31), then set the real sign computed above (d6).
	lsl.l			#8,d0
	lsl.l			#8,d0
	bfins			d6,d0{0:1}

	; Done
	.Done:

endm


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

	; Emulate instruction
	FE_FADD

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
