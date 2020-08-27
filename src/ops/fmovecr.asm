;
; fmovecr emulation
;
FmovecrHandler

	; Debug instruction
	WRITEDEBUG		#.DEBUGOP,INSTRUCTION

	; Increment PC
	INREMENTPC		#$04
	
	; Emulate instruction
	bfextu			INSTRUCTION{25:7},d0
	movem.l			(CCC,d0.w*8),d0/d1
	
	; Write results
	GETREGISTER		d5
	MOVEDNTOFPN		d5,d0,d1
	
	; Set condition codes
	SETCC			d0,d1
	
	; Done
	rts
	
	; Debug constants
	.DEBUGOP:
	dc.b 			"fmovecr %08lx",10,0
	even