;
; flog2 emulation
;
flog2Handler

	; Debug instruction
	WRITEDEBUG		#.DEBUGOP,INSTRUCTION

	; Increment PC
	INREMENTPC		#$04
	
	; Get data
	GETDATALENGTH	d0
	GETEAVALUE		d0,d1
	
	; Emulate instruction
	movea.l			MathIeeeDoubTransBase,a6
	jsr				_LVOIEEEDPLog10(a6)
	move.l			#$3fd34413,d2
	move.l			#$509f79ff,d3
	movea.l			MathIeeeDoubBasBase,a6
	jsr				_LVOIEEEDPDiv(a6)
		
	; Write results
	GETREGISTER		d5
	MOVEDNTOFPN		d5,d0,d1
	
	; Set condition codes
	SETCC			d0,d1
	
	; Done
	rts
	
	; Debug constants
	.DEBUGOP:
	dc.b 			"flog2 %08lx",10,0
	even	