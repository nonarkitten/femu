;
; fcmp emulation. Extended format (checklist #4): same FAKE+SUB+FAKE+
; SETCC structure as before (see math64.asm's FAKE96/SUB96/ISNAN96 --
; 96-bit, one register wider per operand, otherwise identical porting of
; the existing algorithm; not a redesign of its comparison logic).
;
FcmpHandler
	; Debug instruction
	WRITEDEBUG		#.DEBUGOP,INSTRUCTION

	; Increment PC
	INREMENTPC		#$04

	; Get data -- see fadd.asm's FADDHANDLER for why source is fetched
	; first, into d3/d4/d5.
	GETDATALENGTH	d0
	GETEAVALUE		d3,d4,d5
	GETREGISTER		d6
	MOVEFPNTODN		d6,d0,d1,d2

	; Emulate instruction
	; is d0 nan or infinite, then pass
	ISNAN96			d0, .Done
	ISNAN96			d3, .Swap
	FAKE96			d0,d1,d2
	FAKE96			d3,d4,d5
	SUB96			d0,d1,d2, d3,d4,d5
	FAKE96			d0,d1,d2
.Done:
	; Write results
	; Set condition codes
	SETCC			d0,d1,d2

	; Done
	rts

.Swap
	move.l			d3,d0
	move.l			d4,d1
	move.l			d5,d2
	bra				.Done

	; Debug constants
	.DEBUGOP:
	dc.b 			"fcmp %08lx",10,0
	even
