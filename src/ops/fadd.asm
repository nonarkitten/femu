;
; d0 - destination high -> destination fraction high
; d1 - destination low
; d2 - source high -> source fraction high
; d3 - source low
; d4 - destination sign + exponent
; d5 - source sign + exponent
; d6 - scratch
; d7 - reserved
;
FE_FADD macro

	; Extract exponents
    bfextu			d0{1:11},d4
    bfextu			d2{1:11},d5

	; Fast path: both operands "ordinary" (finite, nonzero, not a
	; denormal -- i.e. exponent in [1,2046])? If so, skip straight past
	; the whole Inf/NaN/zero ladder below -- it only ever special-cases
	; an operand whose exponent is 0 or $7ff, so this range check is an
	; exact, cheap precondition for "the ladder wouldn't have done
	; anything anyway". d6 is free here (not needed again until the
	; sign extraction both paths do next), so no register to restore.
	move.w			d4,d6
	subq.w			#1,d6
	cmp.w			#2046,d6
	bhs.s			.SpecialCase
	move.w			d5,d6
	subq.w			#1,d6
	cmp.w			#2046,d6
	bhs.s			.SpecialCase

	; Ordinary: extract signs and go straight to the real add.
	bfextu			d0{0:1},d6
	bfins			d6,d4{0:1}
	bfextu			d2{0:1},d6
	bfins			d6,d5{0:1}
	bra.w			.MainBody

	.SpecialCase:
    ; Extract signs
    bfextu          d0{0:1},d6
    bfins           d6,d4{0:1}
    bfextu          d2{0:1},d6
    bfins           d6,d5{0:1}

	; Check exponent for infinities and NaNs
	cmp.w 			#$7ff,d4
	bne.s			.DstExpOk
	bra.w			.Done
	.DstExpOk:
	cmp.w 			#$7ff,d5
	bne.s			.SrcExpOk
	move.l			d2,d0
	move.l			d3,d1
	bra.w			.Done
	.SrcExpOk:

	; Check exponent for zeroes
	tst.w			d4
	bne.s			.DstExpNoZ
	move.l			d2,d0
	move.l			d3,d1
	bra.w			.Done
	.DstExpNoZ:
	tst.w			d5
	beq.w			.Done

	.MainBody:
	; Extract fractions
	bfextu			d0{12:20},d0
    bfextu			d2{12:20},d2
	bset			#20,d0
	bset			#20,d2

	; Align exponents
	ALIGNEXPONENT	d4,d0,d1,d5,d2,d3
	
	; Sum mantissas
	btst			#31,d4
	beq.s			.PosA
	NEG64			d0,d1
	.PosA:
	btst			#31,d5
	beq.s			.PosB
	NEG64			d2,d3
	.PosB:
	ADD64			d2,d3,d0,d1
	ABS64			d0,d1
	
	; Normalize
	NORMALIZE		d4,d0,d1,d2
	
	; Construct result
	bfins			d4,d0{1:11}
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
	
	; Get data
	GETDATALENGTH	d0
    ifnb \1
		; TODO: use this with all ops, according to BigGun now all datatypes are being converted
        MOVEFROMC       010,3
        vperm           #$01230123,d3,d3,d2
	else
		GETEAVALUE		d2,d3
	endif
	GETREGISTER		d5
	MOVEFPNTODN		d5,d0,d1
	
	; Emulate instruction
	FE_FADD

	; Write results
	GETREGISTER		d5
	MOVEDNTOFPN		d5,d0,d1
	
	; Set condition codes
	SETCC			d0,d1
	
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
