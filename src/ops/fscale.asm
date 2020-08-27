;
; fscale emulation
;
FscaleHandler

	; Debug instruction
	WRITEDEBUG		#.DEBUGOP,INSTRUCTION

	; Increment PC
	INREMENTPC		#$04
	
	; Get scale factor
	GETDATALENGTH	d0
	GETEAVALUE		d0,d1
	jsr				DoubleToLong
	
	; Emulate instruction
	GETREGISTER		d5
	MOVEFPNTODN		d5,d2,d3
	bfextu			d2{1:11},d1
	add.l			d0,d1
	bfins			d1,d2{1:11}
	
	; Write results
	MOVEDNTOFPN		d5,d2,d3

	; Set condition codes
	SETCC			d2,d3

	; Done
	rts
	
	; Debug constants
	.DEBUGOP:
	dc.b 			"fscale %08lx",10,0
	even