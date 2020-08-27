;
; fneg emulation
;
FnegHandler
FsnegHandler
FdnegHandler

	; Debug instruction
	WRITEDEBUG		#.DEBUGOP,INSTRUCTION
	
	nop
	nop
	nop
	nop
	
	; Increment PC
	INREMENTPC		#$04

	; Get data
	GETDATALENGTH	d0
	GETEAVALUE		d0,d1
	
	; Emulate instruction
	bchg			#31,d0

	; Write results
	GETREGISTER		d5
	MOVEDNTOFPN		d5,d0,d1

	; Set condition codes
	SETCC			d0,d1

	; Done
	rts

	nop
	nop
	nop
	nop
	
	; Debug constants
	.DEBUGOP:
	dc.b 			"fneg %08lx",10,0
	even