;
; fetox emulation
;
FetoxHandler

	; Debug instruction
	WRITEDEBUG		#.DEBUGOP,INSTRUCTION

	; Increment PC
	INREMENTPC		#$04

	; Get data (extended-format operand, checklist #4)
	GETDATALENGTH	d0
	GETEAVALUE		d0,d1,d2

	; Fast path (checklist #9): fetox(0) = e^0 = 1.0 exactly, for
	; either sign of zero -- skip InternalToDouble and the slow
	; library Exp call entirely. Exponent field zero is the complete
	; zero test here (matches the existing denormal-as-zero convention
	; used by FE_FADD/FE_FMUL/FE_FDIV's own ladders -- a denormal
	; operand is already treated as zero elsewhere, so this is
	; consistent, not a new relaxation).
	bfextu			d0{1:15},d6
	bne.s			.NotZero
	move.l			#$3fff0000,d0
	move.l			#$80000000,d1
	moveq			#0,d2
	bra.w			.FastDone
	.NotZero:

	jsr				InternalToDouble

	; Emulate instruction
	movea.l			MathIeeeDoubTransBase,a6
	jsr				_LVOIEEEDPExp(a6)

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
	dc.b 			"fetox %08lx",10,0
	even