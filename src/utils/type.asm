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
; Converts a extended to a double.
;
; INPUTS
;	d0 -- The value to be converted.
;	d1 -- The value to be converted.
;	d2 -- The value to be converted.
;
; RESULT
;	d0 -- Highest 32 bits of the double.
;	d1 -- Lowest 32 bits of the double.
;
; TODO: denormalized nubers...
;	
ExtendedToDouble

	; Store registers to stack
	movem.l		d2/d3/d4,-(sp)

	; Get extended to d2/d3/d4
	move.l		d0,d2
	move.l		d1,d3
	move.l		d2,d4
	
	; Check zero
	move.l		d2,d1
	andi.l		#$7fff0000,d1
	bne.s		.NoZ
	tst.l		d3
	bne.s		.NoZ
	tst.l		d4
	bne.s		.NoZ
	move.l		d2,d0
	bra.s		.GotDouble
	.NoZ:
	
	; Check infinity and NaN
	; TODO: SNaN support?
	cmp.l		#$7fff0000,d1
	bne.s		.NoNaN
	move.l		d3,d1
	andi.l		#$7fffffff,d1
	bne.s		.NoI
	tst.l		d4
	bne.s		.NoI
	move.l		d2,d0
	andi.l		#$fff00000,d0			
	clr.l		d1
	bra.s		.GotDouble
	.NoI:
	move.l		d2,d0
	ori.l		#$7fffffff,d0
	move.l		#$ffffffff,d1
	bra.s		.GotDouble
	.NoNaN:
	
	; Convert 15 bit exponent to 11 bit
	move.l		d2,d0
	subi.l		#1006632960,d0
	lsl.l		#4,d0
	
	; Convert 63 bit mantissa to 52 bit fraction
	bfins		d3,d1{0:11}
	lsr.l		#8,d3
	lsr.l		#3,d3
	bfins		d3,d0{12:20}
	lsr.l		#8,d4
	lsr.l		#3,d4
	bfins		d4,d1{11:21}

	; Copy sign
	btst.l		#31,d2
	beq.s		.NoN
	bset.l		#31,d0
	.NoN:
	
	; Restore registers from stack 
	.GotDouble:
	movem.l		(sp)+,d2/d3/d4
	rts
	
	
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
; Converts a double to a extended.
;
; INPUTS
;	d0 -- Highest 32 bits of the double.
;	d1 -- Lowest 32 bits of the double.
;
; RESULT
;	d0 -- Highest 32 bits of the extended.
;	d1 -- Middle 32 bits of the extended.
;	d2 -- Lowest 32 bits of the extended.
;
; TODO: NaNs, inifnities, zeroes, denormalized...
;	
DoubleToExtended

	; Store registers to stack
	movem.l		d3/d4,-(sp)
	
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
	movem.l		(sp)+,d3/d4
	
	; Done
	rts

	
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
