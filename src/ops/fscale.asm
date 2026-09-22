;
; fscale emulation
;
FscaleHandler

	; Debug instruction
	WRITEDEBUG		#.DEBUGOP,INSTRUCTION

	; Increment PC
	INREMENTPC		#$04
	
	; Get scale factor (extended-format operand, checklist #4 -- convert
	; via the double intermediate since it's just an ordinary integer
	; conversion, unrelated to the internal representation's own math)
	GETDATALENGTH	d0
	GETEAVALUE		d0,d1,d2
	jsr				InternalToLong

	; Emulate instruction (15-bit exponent field now, bias 16383)
	GETREGISTER		d5
	MOVEFPNTODN		d5,d2,d3,d4
	bfextu			d2{1:15},d1
	add.l			d0,d1
	bfins			d1,d2{1:15}

	; Write results
	MOVEDNTOFPN		d5,d2,d3,d4

	; Set condition codes
	SETCC			d2,d3,d4

	; Done
	rts
	
	; Debug constants
	.DEBUGOP:
	dc.b 			"fscale %08lx",10,0
	even