;
; ftst emulation
;
FtstHandler

	; Debug instruction
	WRITEDEBUG		#.DEBUGOP,INSTRUCTION

	; Increment PC
	INREMENTPC		#$04

	; Get data (extended format, checklist #4)
	GETDATALENGTH	d0
	GETEAVALUE		d0,d1,d2

	; Set condition codes
	SETCC			d0,d1,d2

	; Done
	rts
	
	; Debug constants
	.DEBUGOP:
	dc.b 			"ftst %08lx",10,0
	even