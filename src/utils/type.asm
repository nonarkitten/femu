;
; Converts a byte to internal (native extended) format.
;
; INPUTS
;	d0 -- The value to be converted.
;
; RESULT
;	d0 -- Sign(1):exponent(15):reserved(16).
;	d1 -- Mantissa bits 63-32 (explicit integer bit at bit 31).
;	d2 -- Mantissa bits 31-0.
;
ByteToInternal
	jsr			ByteToDouble
	jmp			DoubleToInternal


;
; Converts a byte to a double.
;
; INPUTS
;	d0 -- The value to be converted.
;
; RESULT
;	d0 -- Highest 32 bits of the double.
;	d1 -- Lowest 32 bits of the double.
;
ByteToDouble
	extb.l		d0
	movea.l		MathIeeeDoubBasBase,a6
	jsr			_LVOIEEEDPFlt(a6)
	rts


;
; Converts a word to internal (native extended) format.
;
; INPUTS
;	d0 -- The value to be converted.
;
; RESULT
;	d0 -- Sign(1):exponent(15):reserved(16).
;	d1 -- Mantissa bits 63-32 (explicit integer bit at bit 31).
;	d2 -- Mantissa bits 31-0.
;
WordToInternal
	jsr			WordToDouble
	jmp			DoubleToInternal


;
; Converts a word to a double.
;
; INPUTS
;	d0 -- The value to be converted.
;
; RESULT
;	d0 -- Highest 32 bits of the double.
;	d1 -- Lowest 32 bits of the double.
;
WordToDouble
	ext.l		d0
	movea.l		MathIeeeDoubBasBase,a6
	jsr			_LVOIEEEDPFlt(a6)
	rts


;
; Converts a long to internal (native extended) format.
;
; INPUTS
;	d0 -- The value to be converted.
;
; RESULT
;	d0 -- Sign(1):exponent(15):reserved(16).
;	d1 -- Mantissa bits 63-32 (explicit integer bit at bit 31).
;	d2 -- Mantissa bits 31-0.
;
LongToInternal
	jsr			LongToDouble
	jmp			DoubleToInternal


;
; Converts a long to a double.
;
; INPUTS
;	d0 -- The value to be converted.
;
; RESULT
;	d0 -- Highest 32 bits of the double.
;	d1 -- Lowest 32 bits of the double.
;
LongToDouble
	movea.l		MathIeeeDoubBasBase,a6
	jsr			_LVOIEEEDPFlt(a6)
	rts


;
; Converts a single to internal (native extended) format.
;
; INPUTS
;	d0 -- The value to be converted.
;
; RESULT
;	d0 -- Sign(1):exponent(15):reserved(16).
;	d1 -- Mantissa bits 63-32 (explicit integer bit at bit 31).
;	d2 -- Mantissa bits 31-0.
;
SingleToInternal
	jsr			SingleToDouble
	jmp			DoubleToInternal


;
; Converts a single to a double.
;
; INPUTS
;	d0 -- The value to be converted.
;
; RESULT
;	d0 -- Highest 32 bits of the double.
;	d1 -- Lowest 32 bits of the double.
;
SingleToDouble
	movea.l		MathIeeeDoubTransBase,a6
	jsr			_LVOIEEEDPFieeee(a6)
	rts


;
; Converts internal (native extended) format to a double. Fixes a
; long-standing bug in this conversion's mantissa handling (found via
; bench/'s fmove probe while designing checklist #4): the previous
; version overwrote its own d2 input (mantissa lo32) with a copy of d0
; (sign+exponent) *before* stashing d2 away, permanently losing the real
; mantissa lo32 and replacing it with garbage -- e.g. extended 1.5 came
; back as 1.5000000001164082 instead of exactly 1.5. This version stashes
; all three inputs into scratch registers before touching anything, and
; isolates the sign bit from the exponent field before rebiasing so a
; borrow during the exponent subtraction can never corrupt the sign (the
; previous version rebiased sign+exponent together in one subtraction).
;
; INPUTS
;	d0 -- Sign(1):exponent(15):reserved(16).
;	d1 -- Mantissa bits 63-32 (explicit integer bit at bit 31).
;	d2 -- Mantissa bits 31-0.
;
; RESULT
;	d0 -- Highest 32 bits of the double.
;	d1 -- Lowest 32 bits of the double.
;
; TODO: denormalized numbers, and extended values outside a double's
;       representable range, aren't renormalized/clamped -- same
;       pre-existing limitation this conversion always had.
;
InternalToDouble

	; Store registers to stack
	movem.l		d2/d3/d4,-(sp)

	; Stash inputs: d3 = sign+exponent+reserved, d4 = mantissa hi32.
	; d2 (mantissa lo32) is already the right input register -- left
	; alone, not overwritten before use (that was the bug).
	move.l		d0,d3
	move.l		d1,d4

	; Check zero: exponent field (sign excluded) and both mantissa words
	move.l		d3,d1
	andi.l		#$7fff0000,d1
	bne.s		.NoZ
	tst.l		d4
	bne.s		.NoZ
	tst.l		d2
	bne.s		.NoZ
	move.l		d3,d0
	moveq		#0,d1
	bra.w		.GotDouble
	.NoZ:

	; Check infinity and NaN (exponent field == $7fff)
	; TODO: SNaN support?
	cmp.l		#$7fff0000,d1
	bne.s		.NoNaN
	; Infinity iff mantissa is exactly the explicit-integer-bit-only
	; pattern; anything else with this exponent is NaN.
	cmp.l		#$80000000,d4
	bne.s		.NoI
	tst.l		d2
	bne.s		.NoI
	move.l		d3,d0
	andi.l		#$fff00000,d0
	moveq		#0,d1
	bra.w		.GotDouble
	.NoI:
	move.l		d3,d0
	ori.l		#$7fffffff,d0
	move.l		#$ffffffff,d1
	bra.w		.GotDouble
	.NoNaN:

	; Rebias the 15-bit exponent (bias 16383) to 11-bit (bias 1023).
	; Sign is isolated first so a borrow during the subtraction can never
	; touch it. Both fields start at bit 16 of their register; the
	; double's field is 4 bits narrower and sits 4 bits higher (bits
	; 30-20 vs 30-16), so subtract the bias delta pre-shifted to bit 16,
	; then shift the result left 4.
	move.l		d3,d0
	andi.l		#$80000000,d0
	move.l		d3,d1
	andi.l		#$7fff0000,d1
	subi.l		#1006632960,d1
	lsl.l		#4,d1
	or.l		d1,d0

	; Strip the explicit integer bit (d4 bit 31) and take the top 52
	; bits of the remaining 63-bit fraction (d4{30:0}:d2{31:0}) as the
	; double's 52-bit fraction.
	bfextu		d4{1:20},d1				; fraction[62:43] -> double fraction[51:32]
	or.l		d1,d0
	bfextu		d4{21:11},d1			; fraction[42:32], right-justified
	lsl.l		#8,d1
	lsl.l		#8,d1
	lsl.l		#5,d1					; -> bits 31-21 of the double's low word
	bfextu		d2{0:21},d3				; fraction[31:11] -> double's low word bits 20-0
	or.l		d3,d1

	; Round to nearest, ties to even, on the 11 fraction bits just
	; dropped (the extended mantissa's own low 11 bits, d2 bits 10-0 --
	; d2/d4 are read-only above, so they're still intact here). This
	; conversion is on a far hotter path now than when it only served
	; the rare .x memory format (every fmul/fdiv/transcendental readout
	; goes through it), so unlike truncation -- fine for an occasional
	; .x round-trip -- silently dropping a rounding bit here would
	; measurably bias results.
	btst.l		#10,d2
	beq.s		.NoRoundUp
	move.l		d2,d3
	andi.l		#$3ff,d3
	bne.s		.RoundUp
	btst.l		#0,d1
	beq.s		.NoRoundUp
	.RoundUp:
	addq.l		#1,d1
	bcc.s		.NoRoundUp
	addq.l		#1,d0
	.NoRoundUp:

	; Restore registers from stack
	.GotDouble:
	movem.l		(sp)+,d2/d3/d4
	rts


;
; Converts a packed to internal (native extended) format.
;
; INPUTS
;	d0/d1/d2 -- The value to be converted.
;
; RESULT
;	d0 -- Sign(1):exponent(15):reserved(16).
;	d1 -- Mantissa bits 63-32 (explicit integer bit at bit 31).
;	d2 -- Mantissa bits 31-0.
;
PackedToInternal
	jsr			PackedToDouble
	jmp			DoubleToInternal


;
; Converts a packed to a double.
;
; INPUTS
;	d0 -- The value to be converted.
;
; RESULT
;	d0 -- Highest 32 bits of the double.
;	d1 -- Lowest 32 bits of the double.
;
; TODO: Implement packed to double conversion
;
PackedToDouble
	; TODO: for devpac
	move.l		#0,d0
	move.l		#0,d1
	;lea		ERRPACKEDTODOUBLE,a0
	;jmp		Unsupported
	rts


;
; Converts internal (native extended) format to a byte.
;
; INPUTS
;	d0 -- Sign(1):exponent(15):reserved(16).
;	d1 -- Mantissa bits 63-32 (explicit integer bit at bit 31).
;	d2 -- Mantissa bits 31-0.
;
; RESULT
;	d0 -- Converted byte.
;
InternalToByte
	jsr			InternalToDouble
	jmp			DoubleToByte


;
; Converts a double to a byte.
;
; INPUTS
;	d0 -- Highest 32 bits of the double.
;	d1 -- Lowest 32 bits of the double.
;
; RESULT
;	d0 -- Converted byte.
;
DoubleToByte
	; TODO: VERY VERY VERY WIP
	; TODO: test with fmove to ea and from ea
	; TODO: test with fmovem
	; TODO: generally testalot
	movea.l		MathIeeeDoubBasBase,a6
	jsr			_LVOIEEEDPFix(a6)
	cmp.l		#-128,d0
	bge			.Ge
	move.l		#-128,d0
	bra.s		.Le
	.Ge:
	cmp.l		#127,d0
	ble			.Le
	move.l		#127,d0
	.Le:
	rts


;
; Converts internal (native extended) format to a word.
;
; INPUTS
;	d0 -- Sign(1):exponent(15):reserved(16).
;	d1 -- Mantissa bits 63-32 (explicit integer bit at bit 31).
;	d2 -- Mantissa bits 31-0.
;
; RESULT
;	d0 -- Converted word.
;
InternalToWord
	jsr			InternalToDouble
	jmp			DoubleToWord


;
; Converts a double to a word.
;
; INPUTS
;	d0 -- Highest 32 bits of the double.
;	d1 -- Lowest 32 bits of the double.
;
; RESULT
;	d0 -- Converted word.
;
DoubleToWord
	; TODO: VERY VERY VERY WIP
	; TODO: test with fmove to ea and from ea
	; TODO: test with fmovem
	; TODO: generally testalot
	movea.l		MathIeeeDoubBasBase,a6
	jsr			_LVOIEEEDPFix(a6)
	cmp.l		#-32768,d0
	bge			.Ge
	move.l		#-32768,d0
	bra.s		.Le
	.Ge:
	cmp.l		#32767,d0
	ble			.Le
	move.l		#32767,d0
	.Le:
	rts


;
; Converts internal (native extended) format to a long.
;
; INPUTS
;	d0 -- Sign(1):exponent(15):reserved(16).
;	d1 -- Mantissa bits 63-32 (explicit integer bit at bit 31).
;	d2 -- Mantissa bits 31-0.
;
; RESULT
;	d0 -- Converted long.
;
InternalToLong
	jsr			InternalToDouble
	jmp			DoubleToLong


;
; Converts a double to a long.
;
; INPUTS
;	d0 -- Highest 32 bits of the double.
;	d1 -- Lowest 32 bits of the double.
;
; RESULT
;	d0 -- Converted long.
;
DoubleToLong
	movea.l		MathIeeeDoubBasBase,a6
	jsr			_LVOIEEEDPFix(a6)
	rts


;
; Converts internal (native extended) format to a single.
;
; INPUTS
;	d0 -- Sign(1):exponent(15):reserved(16).
;	d1 -- Mantissa bits 63-32 (explicit integer bit at bit 31).
;	d2 -- Mantissa bits 31-0.
;
; RESULT
;	d0 -- Converted single.
;
InternalToSingle
	jsr			InternalToDouble
	jmp			DoubleToSingle


;
; Converts a double to a single.
;
; INPUTS
;	d0 -- Highest 32 bits of the double.
;	d1 -- Lowest 32 bits of the double.
;
; RESULT
;	d0 -- Converted single.
;
DoubleToSingle
	movea.l		MathIeeeDoubTransBase,a6
	jsr			_LVOIEEEDPTieee(a6)
	rts


;
; Converts a double to internal (native extended) format. Adds zero/
; infinity/NaN special-casing this conversion never had before (its
; previous only caller was the register-direct fmove.x/fmovem.x path,
; where a raw copy handled those values already -- this function's own
; math never saw them). Now every fmove.d/fmovecr/transcendental-library
; result also flows through here, so the gap needed closing: without it,
; e.g. an incoming double zero produced extended exponent 15360 with the
; explicit integer bit forced on -- a normalized nonzero value, not zero.
;
; INPUTS
;	d0 -- Highest 32 bits of the double.
;	d1 -- Lowest 32 bits of the double.
;
; RESULT
;	d0 -- Sign(1):exponent(15):reserved(16).
;	d1 -- Mantissa bits 63-32 (explicit integer bit at bit 31).
;	d2 -- Mantissa bits 31-0.
;
; TODO: NaNs, infinities, zeroes now handled; denormalized still isn't.
;
DoubleToInternal

	; Store registers to stack
	movem.l		d3/d4,-(sp)

	; Check zero: sign-cleared d0 and all of d1 zero. d0's sign bit is
	; already the only thing that can be set in this case, so it's left
	; untouched -- already the correct extended-zero result.
	move.l		d0,d2
	andi.l		#$7fffffff,d2
	bne.s		.NoZ
	tst.l		d1
	bne.s		.NoZ
	moveq		#0,d1
	moveq		#0,d2
	bra.w		.GotExtended
	.NoZ:

	; Check infinity and NaN (double exponent field all-ones, $7ff)
	move.l		d0,d2
	andi.l		#$7ff00000,d2
	cmp.l		#$7ff00000,d2
	bne.s		.NoNaN
	move.l		d0,d2
	andi.l		#$000fffff,d2
	bne.s		.NoI
	tst.l		d1
	bne.s		.NoI
	; Infinity: sign + all-ones extended exponent, explicit-bit-only mantissa
	andi.l		#$80000000,d0
	ori.l		#$7fff0000,d0
	move.l		#$80000000,d1
	moveq		#0,d2
	bra.w		.GotExtended
	.NoI:
	; NaN: sign + all-ones extended exponent, all-ones mantissa
	andi.l		#$80000000,d0
	ori.l		#$7fff0000,d0
	move.l		#$ffffffff,d1
	move.l		#$ffffffff,d2
	bra.w		.GotExtended
	.NoNaN:

	; Convert 52 bit fraction to integer bit and 63 bit mantissa
	bfextu		d0{12:20},d3
	lsl.l		#8,d3
	lsl.l		#3,d3
	bfextu		d1{0:11},d4
	bfins		d4,d3{21:11}
	bset.l		#31,d3
	move.l		d1,d4
	lsl.l		#8,d4
	lsl.l		#3,d4

	; Convert 11 bit exponent to 15 bit exponent
	bfextu		d0{1:11},d2
	addi.l		#15360,d2
	swap		d2

	; Copy sign
	btst.l		#31,d0
	beq.s		.NoN
	bset.l		#31,d2
	.NoN:

	; Copy results to d0/d1/d2
	move.l		d2,d0
	move.l		d3,d1
	move.l		d4,d2

	; Restore registers from stack
	.GotExtended:
	movem.l		(sp)+,d3/d4

	; Done
	rts


;
; Converts internal (native extended) format to a packed.
;
; INPUTS
;	d0 -- Sign(1):exponent(15):reserved(16).
;	d1 -- Mantissa bits 63-32 (explicit integer bit at bit 31).
;	d2 -- Mantissa bits 31-0.
;
; RESULT
;	d0 -- Converted packed.
;
InternalToPacked
	jsr			InternalToDouble
	jmp			DoubleToPacked


;
; Converts a double to a packed.
;
; INPUTS
;	d0 -- Highest 32 bits of the double.
;	d1 -- Lowest 32 bits of the double.
;
; RESULT
;	d0 -- Converted packed.
;
; TODO: Implement double to extended conversion
;
DoubleToPacked
	; TODO: for devpac
	move.l		#0,d0
	move.l		#0,d1
	;lea		ERRDOUBLETOPACKED,a0
	;jmp		Unsupported
	rts
