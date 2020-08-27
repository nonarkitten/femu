;
; TODO: this seems to be bugged, at least 080 hw fmovem fixes problems!
;


;
; 
;
GETFMOVELENGTH macro
	bfextu		INSTRUCTION{24:8},\1
	move.b		(FMOVEMLENGTHS,d0.w),\1
endm


;
;
;
GETFMOVEMREGS macro
	btst		#11,INSTRUCTION
	beq.s		.\@Static
    
    .\@Dynamic:
	lea.l		ERRUNSUPPORTEDREGLIST,a0
	jmp			Unsupported
    
	.\@Reverse:
	REVERSEBYTE \1
	bra.s       .\@GotIt
    
	.\@Static:
	move.b		INSTRUCTION,\1
	btst		#12,INSTRUCTION
	bne.s		.\@Reverse
    
    .\@GotIt:
endm


;
;
;
FMOVEMEAFPN macro
	btst.l			#\1,\2
	beq.s			.\@NoMove
    movem.l			(a3),d0/d1/d2
	jsr				ExtendedToDouble
    move.l          #\1,d5
	MOVEDNTOFPN     d5,d0,d1
    adda.l			#$0c,a3
    .\@NoMove:
endm


;
;
;
FMOVEMFPNEA macro
	btst.l			#\1,\2
	beq.s			.\@NoMove
    move.l          #\1,d5
	MOVEFPNTODN		d5,d0,d1
	jsr				DoubleToExtended
    movem.l			d0/d1/d2,(a3)
	adda.l			#$0c,a3
    .\@NoMove:
endm


;
; fmovem ea to register emulation
;
FmovemEaRegHandler
	WRITEDEBUG		#.DEBUGOP,INSTRUCTION
	INREMENTPC		#$04
	GETFMOVELENGTH  d0
	GETEA			a3
	GETFMOVEMREGS   d4
	FMOVEMEAFPN		0,d4
	FMOVEMEAFPN		1,d4
	FMOVEMEAFPN		2,d4
	FMOVEMEAFPN		3,d4
	FMOVEMEAFPN		4,d4
	FMOVEMEAFPN		5,d4
	FMOVEMEAFPN		6,d4
	FMOVEMEAFPN		7,d4
	rts
	.DEBUGOP:
	dc.b 			"fmovem ea,reg %08lx",10,0
	even

	
;
; fmovem register to ea emulation
;
FmovemRegEaHandler
	WRITEDEBUG		#.DEBUGOP,INSTRUCTION
	INREMENTPC	    #$04   
	GETFMOVELENGTH  d0
	GETEA		    a3
	GETFMOVEMREGS   d4
	FMOVEMFPNEA	    0,d4
	FMOVEMFPNEA	    1,d4
	FMOVEMFPNEA	    2,d4
	FMOVEMFPNEA	    3,d4
	FMOVEMFPNEA	    4,d4
	FMOVEMFPNEA	    5,d4
	FMOVEMFPNEA	    6,d4
	FMOVEMFPNEA	    7,d4
	rts
	.DEBUGOP:
	dc.b 			"fmovem reg,ea %08lx",10,0
	even

;
;
;	
FMOVEMLENGTHS
	dc.b	00,12,12,24,12,24,24,36,12,24,24,36,24,36,36,48
    dc.b	12,24,24,36,24,36,36,48,24,36,36,48,36,48,48,60
	dc.b	12,24,24,36,24,36,36,48,24,36,36,48,36,48,48,60
    dc.b	24,36,36,48,36,48,48,60,36,48,48,60,48,60,60,72
	dc.b	12,24,24,36,24,36,36,48,24,36,36,48,36,48,48,60
    dc.b	24,36,36,48,36,48,48,60,36,48,48,60,48,60,60,72
	dc.b	24,36,36,48,36,48,48,60,36,48,48,60,48,60,60,72
    dc.b	36,48,48,60,48,60,60,72,48,60,60,72,60,72,72,84
	dc.b	12,24,24,36,24,36,36,48,24,36,36,48,36,48,48,60
    dc.b	24,36,36,48,36,48,48,60,36,48,48,60,48,60,60,72
	dc.b	24,36,36,48,36,48,48,60,36,48,48,60,48,60,60,72
    dc.b	36,48,48,60,48,60,60,72,48,60,60,72,60,72,72,84
	dc.b	24,36,36,48,36,48,48,60,36,48,48,60,48,60,60,72
    dc.b	36,48,48,60,48,60,60,72,48,60,60,72,60,72,72,84
	dc.b	36,48,48,60,48,60,60,72,48,60,60,72,60,72,72,84
    dc.b	48,60,60,72,60,72,72,84,60,72,72,84,72,84,84,96	