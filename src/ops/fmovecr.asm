;
; fmovecr emulation
;
FmovecrHandler

	; Debug instruction
	WRITEDEBUG		#.DEBUGOP,INSTRUCTION

	; Increment PC
	INREMENTPC		#$04
	
	; Emulate instruction -- CCC's constants are stored as doubles, so
	; the lookup needs one DoubleToInternal conversion (checklist #4).
	; This op is cold (rare), so the cost doesn't matter -- see
	; DESIGN-04-native-extended-repr.md.
	bfextu			INSTRUCTION{25:7},d0
	movem.l			(CCC,d0.w*8),d0/d1
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
	dc.b 			"fmovecr %08lx",10,0
	even