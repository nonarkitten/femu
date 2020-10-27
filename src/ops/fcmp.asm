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
	; is d0 nan or infinite, then pass
	ISNAN			d0, .Done
	ISNAN			d2, .Swap
	FAKE64			d0,d1
	FAKE64			d2,d3
	SUB64			d0,d1, d2,d3
	FAKE64			d0,d1
.Done:
	; Write results		
	; Set condition codes
	SETCC			d0,d1
	
	; Done
	rts
	
.Swap
	move.l			d2,d0
	move.l			d3,d1
	bra				.Done
	
	; Debug constants
	.DEBUGOP:
	dc.b 			"fcmp %08lx",10,0
	even
