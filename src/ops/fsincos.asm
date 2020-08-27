;
; fsincos emulation
;
FsincosHandler

	; Debug instruction
	WRITEDEBUG		#.DEBUGOP,INSTRUCTION
		
	; Increment PC
	INREMENTPC		#$04
	
	; Get data
	GETDATALENGTH	d0
	GETEAVALUE		d0,d1

	; Emulate instruction
	suba.l			#8,sp
	move.l			sp,a0
	movea.l			MathIeeeDoubTransBase,a6
	jsr				_LVOIEEEDPSincos(a6)

	; Write results
	GETREGISTER		d5
	MOVEDNTOFPN		d5,d0,d1
	movem.l			(sp)+,d0/d1
	GETREGISTER		d5,29
	MOVEDNTOFPN		d5,d0,d1
	
	; Set condition codes 
	SETCC			d0,d1

	; Done
	rts
	
	; Debug constants
	.DEBUGOP:
	dc.b 			"fsincos %08lx",10,0
	even	
