;
; fsincos emulation
;
FsincosHandler

	; Debug instruction
	WRITEDEBUG		#.DEBUGOP,INSTRUCTION
		
	; Increment PC
	INREMENTPC		#$04
	
	; Get data (extended-format operand, checklist #4)
	GETDATALENGTH	d0
	GETEAVALUE		d0,d1,d2
	jsr				InternalToDouble

	; Emulate instruction
	suba.l			#8,sp
	move.l			sp,a0
	movea.l			MathIeeeDoubTransBase,a6
	jsr				_LVOIEEEDPSincos(a6)
	jsr				DoubleToInternal

	; Write results
	GETREGISTER		d5
	MOVEDNTOFPN		d5,d0,d1,d2
	movem.l			(sp)+,d0/d1
	jsr				DoubleToInternal
	GETREGISTER		d5,29
	MOVEDNTOFPN		d5,d0,d1,d2

	; Set condition codes
	SETCC			d0,d1,d2

	; Done
	rts
	
	; Debug constants
	.DEBUGOP:
	dc.b 			"fsincos %08lx",10,0
	even	
