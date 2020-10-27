;
; fabs emulation
;
FabsHandler
FsabsHandler
FdabsHandler
	; Debug instruction
	WRITEDEBUG		#.DEBUGOP,INSTRUCTION

	; Increment PC
	INREMENTPC		#$04
	
	; Get data
	GETDATALENGTH	d0
	GETEAVALUE		d0,d1
	
	; Emulate instruction
	bclr			#31,d0
	
	; Write results
	GETREGISTER		d5
	MOVEDNTOFPN		d5,d0,d1
	
	; Set condition codes
	SETCC			d0,d1
	
	; Done
	rts

	; Debug constants
	.DEBUGOP:
	dc.b 			"fabs %08lx",10,0
	even
