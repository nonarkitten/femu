;
; ftentox emulation
;
FtentoxHandler

	; Debug instruction
	WRITEDEBUG		#.DEBUGOP,INSTRUCTION
	
	; Increment PC
	INREMENTPC		#$04

	; Get data (extended-format operand, checklist #4 -- converted to
	; double, then moved into d2/d3 since IEEEDPPow's exponent argument
	; goes there, base 10.0 hardcoded into d0/d1)
	GETDATALENGTH	d0
	GETEAVALUE		d0,d1,d2
	jsr				InternalToDouble
	move.l			d0,d2
	move.l			d1,d3
	move.l			#$40240000,d0
	move.l			#$00000000,d1

	; Emulate instruction
	movea.l			MathIeeeDoubTransBase,a6
	jsr				_LVOIEEEDPPow(a6)
	jsr				DoubleToInternal

	; Write results
	GETREGISTER		d5
	MOVEDNTOFPN		d5,d0,d1,d2

	; Set condition codes
	SETCC			d0,d1,d2

	; Done
	rts
	
	; Debug constants
	.DEBUGOP:
	dc.b 			"ftentox %08lx",10,0
	even