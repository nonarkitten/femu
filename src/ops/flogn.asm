;
; flogn emulation
;
FlognHandler

	; Debug instruction
	WRITEDEBUG		#.DEBUGOP,INSTRUCTION
	
	; Increment PC
	INREMENTPC		#$04

	; Get data (extended-format operand, checklist #4)
	GETDATALENGTH	d0
	GETEAVALUE		d0,d1,d2

	; Fast path (checklist #9): flogn(1) = ln(1) = 0.0 exactly -- skip
	; InternalToDouble and the slow library Log call entirely. Must be
	; exactly +1.0 (sign clear, biased exponent 16383, explicit-bit-
	; only mantissa) -- -1.0 is deliberately excluded (ln(-1) is NaN,
	; not 0).
	cmp.l			#$3fff0000,d0
	bne.s			.NotOne
	cmp.l			#$80000000,d1
	bne.s			.NotOne
	tst.l			d2
	bne.s			.NotOne
	moveq			#0,d0
	moveq			#0,d1
	moveq			#0,d2
	bra.w			.FastDone
	.NotOne:

	jsr				InternalToDouble

	; Emulate instruction
	movea.l			MathIeeeDoubTransBase,a6
	jsr				_LVOIEEEDPLog(a6)

	; Write results
	jsr				DoubleToInternal
	.FastDone:
	GETREGISTER		d5
	MOVEDNTOFPN		d5,d0,d1,d2

	; Set condition codes
	SETCC			d0,d1,d2

	; Done
	rts
	
	; Debug constants
	.DEBUGOP:
	dc.b 			"flogn %08lx",10,0
	even