;
; fsqrt emulation
;
FsqrtHandler
FssqrtHandler
FdsqrtHandler

	; Debug instruction
	WRITEDEBUG		#.DEBUGOP,INSTRUCTION
		
	; Increment PC
	INREMENTPC		#$04

	; Get data (extended-format operand, checklist #4)
	GETDATALENGTH	d0
	GETEAVALUE		d0,d1,d2

	; Fast path (checklist #9): fsqrt(0) = 0 and fsqrt(+1) = +1 are
	; both exactly self-identical results -- skip InternalToDouble and
	; the slow library Sqrt call entirely, leaving d0/d1/d2 completely
	; untouched. The zero check ignores sign (sqrt(-0) = -0, still
	; self-identical, and matches the existing denormal-as-zero
	; convention). The one check requires sign clear: -1.0 is
	; deliberately excluded (sqrt(-1) is NaN, not -1).
	bfextu			d0{1:15},d6
	beq.w			.FastDone
	cmp.l			#$3fff0000,d0
	bne.s			.NotOne
	cmp.l			#$80000000,d1
	bne.s			.NotOne
	tst.l			d2
	beq.w			.FastDone
	.NotOne:

	jsr				InternalToDouble

	; Emulate instruction
	movea.l			MathIeeeDoubTransBase,a6
	jsr				_LVOIEEEDPSqrt(a6)

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
	dc.b 			"fsqrt %08lx",10,0
	even