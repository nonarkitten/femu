;
;
;
FDIVHANDLER macro

	; Debug instruction
	WRITEDEBUG		#.DEBUGOP,INSTRUCTION

	; Increment PC
	INREMENTPC		#$04

	; Get data
	GETDATALENGTH	d0
	GETEAVALUE		d2,d3
	GETREGISTER		d5
	MOVEFPNTODN		d5,d0,d1

	 ; Emulate instruction
	 movea.l		MathIeeeDoubBasBase,a6
	 jsr			_LVOIEEEDPDiv(a6)

	; Write results
	MOVEDNTOFPN		d5,d0,d1
	
	; Set condition codes
	SETCC			d0,d1
	
endm


;
; fdiv emulation
;
FdivHandler
FsdivHandler
FddivHandler
FsgldivHandler
	FDIVHANDLER
	rts

	; Debug constants
	.DEBUGOP:
	dc.b 			"fdiv %08lx",10,0
	even
const_025:	dc.l	$3fd00000,$0

