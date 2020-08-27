; First, convert the two representations to scientific notation. Thus, we explicitly represent the hidden 1. 
; Let x be the exponent of X. Let y be the exponent of Y. The resulting exponent (call it z) is the sum of the two exponents. z may need to be adjusted after the next step. 
; Multiply the mantissa of X to the mantissa of Y. Call this result m. 
; If m is does not have a single 1 left of the radix point, then adjust the radix point so it does, and adjust the exponent z to compensate. 
; Add the sign bits, mod 2, to get the sign of the resulting multiplication. 
; Convert back to the one byte floating point representation, truncating bits if needed.

;
; CAUTION: UNFINISHED
;
FE_FMUL macro

	; Extract exponents
    bfextu			d0{1:11},d4
    bfextu			d2{1:11},d5

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

	; Extract fractions
	bfextu			d0{12:20},d0
    bfextu			d2{12:20},d2
	bset			#20,d0
	bset			#20,d2
	
	; Align exponents
	ALIGNEXPONENT	d4,d0,d1,d5,d2,d3
	
	; Sum exponents
	;add.w			d5,d4	; TODO: this will crash it due to overflows
	
	; Multiply mantissas
	; TODO: MUL64!
	ADD64			d2,d3,d0,d1
	
	; Normalize
	NORMALIZE		d4,d0,d1,d2,d3
	
	; Construct result
	bfins			d4,d0{1:11}
	bfins			d6,d0{0:1}
	
	; Done
	.Done:
	
endm
	

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
	;ifd NOMATHLIB
	;	FMUL
	;else
		movea.l			MathIeeeDoubBasBase,a6
		jsr				_LVOIEEEDPMul(a6)
	;endif

	; Write results
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
