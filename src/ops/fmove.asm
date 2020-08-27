;
; fmove ea to register handler
;
FmoveEaRegHandler
	WRITEDEBUG		#.DEBUGOP,INSTRUCTION
	INREMENTPC		#$04
	GETREGISTER		d5
	GETDATALENGTH	d0
	GETEAVALUE		d2,d3
	MOVEDNTOFPN		d5,d2,d3
	SETCC			d2,d3
	rts
	.DEBUGOP:
	dc.b 			"fmovem ea,reg %08lx",10,0
	even
	
	
;
; fmove register to ea handler
;
FmoveRegEaHandler
	WRITEDEBUG		#.DEBUGOP,INSTRUCTION
	INREMENTPC		#$04
	GETDATALENGTH	d0
	GETEA			a3
	GETREGISTER		d5
	bfextu			INSTRUCTION{19:3},d0
	jmp				(FmoveRegEaHandlerVectors,d0.w*4)
	.DEBUGOP:
	dc.b 			"fmove reg,ea %08lx",10,0
	even

	
;
;
; 
FmoveRegEaByte
	MOVEFPNTODN			d5,d0,d1
	jsr					DoubleToByte
	move.b				d0,(a3)
	rts

	
;
;
; 
FmoveRegEaWord
	MOVEFPNTODN			d5,d0,d1
	jsr					DoubleToWord
	move.w				d0,(a3)
	rts

	
;
;
; 
FmoveRegEaLong
	MOVEFPNTODN			d5,d0,d1
	jsr					DoubleToLong
	move.l				d0,(a3)
	rts


;
;
; 
FmoveRegEaSingle
	MOVEFPNTODN			d5,d0,d1
	jsr					DoubleToSingle
	move.l				d0,(a3)
	rts

	
;
;
; 
FmoveRegEaDouble
	MOVEFPNTODN			d5,d0,d1
	movem.l				d0/d1,(a3)
	rts

	
;
;
; 
FmoveRegEaExtended
	MOVEFPNTODN			d5,d0,d1
	jsr					DoubleToExtended
	movem.l				d0/d1/d2,(a3)
	rts
	
	
;
;
; 
FmoveRegEaPacked
	MOVEFPNTODN			d5,d0,d1
	jsr					DoubleToPacked
	movem.l				d0/d1/d2,(a3)
	rts	

	
;
;
;	
FmoveRegEaHandlerVectors
	bra.w	FmoveRegEaLong		; 000 long
	bra.w	FmoveRegEaSingle	; 001 single
	bra.w	FmoveRegEaExtended	; 010 extended
	bra.w	FmoveRegEaPacked	; 011 packed
	bra.w	FmoveRegEaWord		; 100 word
	bra.w	FmoveRegEaDouble	; 101 double
	bra.w	FmoveRegEaByte		; 110 byte
	bra.w	Unsupported			; 111 unused		
