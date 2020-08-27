;
; ftwotox emulation
;
FtwotoxHandler

	; Debug instruction
	WRITEDEBUG		#.DEBUGOP,INSTRUCTION
		
	; Increment PC
	INREMENTPC		#$04

	; Get data
	GETDATALENGTH	d0
	GETEAVALUE		d2,d3
	move.l			#$40000000,d0
	move.l			#$00000000,d1
	
	; Emulate instruction
	movea.l			MathIeeeDoubTransBase,a6
	jsr				_LVOIEEEDPPow(a6)

	; Write results
	GETREGISTER		d5
	MOVEDNTOFPN		d5,d0,d1

	; Set condition codes
	SETCC			d0,d1

	; Done
	rts
	
	; Debug constants
	.DEBUGOP:
	dc.b 			"ftwotox %08lx",10,0
	even