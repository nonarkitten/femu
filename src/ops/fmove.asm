;
; fmove ea to register handler
;
FmoveEaRegHandler
	WRITEDEBUG		#.DEBUGOP,INSTRUCTION
	INREMENTPC		#$04
	GETREGISTER		d5
	GETDATALENGTH	d0
	; d0/d1/d2 (not d2/d3/d4): GETEAVALUE's underlying GetEaValue always
	; returns through d0/d1/d2, and its macro expansion is a sequence
	; of plain move.l's, not a simultaneous/atomic assignment -- asking
	; it to land in d2/d3/d4 let the first move (d0->d2) clobber d2
	; before the third move could still read it as GetEaValue's own
	; mantissa-lo output, corrupting every fmove ea,reg. d5 (the FPn
	; index from GETREGISTER above) survives GETDATALENGTH/GETEAVALUE
	; untouched, same as every other handler relies on.
	GETEAVALUE		d0,d1,d2
	MOVEDNTOFPN		d5,d0,d1,d2
	SETCC			d0,d1,d2
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
	MOVEFPNTODN			d5,d0,d1,d2
	jsr					InternalToByte
	move.b				d0,(a3)
	rts


;
;
;
FmoveRegEaWord
	MOVEFPNTODN			d5,d0,d1,d2
	jsr					InternalToWord
	move.w				d0,(a3)
	rts


;
;
;
FmoveRegEaLong
	MOVEFPNTODN			d5,d0,d1,d2
	jsr					InternalToLong
	move.l				d0,(a3)
	rts


;
;
;
FmoveRegEaSingle
	MOVEFPNTODN			d5,d0,d1,d2
	jsr					InternalToSingle
	move.l				d0,(a3)
	rts


;
;
;
FmoveRegEaDouble
	MOVEFPNTODN			d5,d0,d1,d2
	jsr					InternalToDouble
	movem.l				d0/d1,(a3)
	rts


;
; Extended: memory layout is byte-identical to the internal format
; (checklist #4's whole point) -- straight copy, no conversion call.
;
FmoveRegEaExtended
	MOVEFPNTODN			d5,d0,d1,d2
	movem.l				d0/d1/d2,(a3)
	rts


;
;
;
FmoveRegEaPacked
	MOVEFPNTODN			d5,d0,d1,d2
	jsr					InternalToPacked
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
