;
; fcmp emulation
;
FcmpHandler

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
	movea.l			MathIeeeDoubBasBase,a6
	jsr				_LVOIEEEDPSub(a6)
	
	; Set condition codes
	SETCC			d0,d1
	
	; Done
	rts
	
	; Debug constants
	.DEBUGOP:
	dc.b 			"fcmp %08lx",10,0
	even