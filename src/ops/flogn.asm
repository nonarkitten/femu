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

	; Native ln(x) (checklist #10): no library call anywhere in this op
	; any more.
	;
	; Zero (either sign, denormal-as-zero convention): ln(0) = -Inf, a
	; pole error -- matches every host libm's behaviour (same
	; convention checked elsewhere in this codebase).
	bfextu			d0{1:15},d6
	bne.s			.NotZero
	move.l			#$ffff0000,d0
	move.l			#$80000000,d1
	moveq			#0,d2
	bra.w			.FastDone
	.NotZero:

	; Infinity/NaN (exponent field all-ones): +Inf passes through
	; unchanged (ln(+Inf)=+Inf, self-identical); -Inf constructs a NaN
	; (ln of a negative value, even an infinite one, isn't real); an
	; actual NaN passes through unchanged -- discriminated the same way
	; SETCC itself does (a mantissa that ISN'T the clean explicit-bit-
	; only Infinity pattern is a NaN, not Infinity).
	cmp.l			#32767,d6
	bne.s			.Finite
	cmp.l			#$80000000,d1
	bne.w			.FastDone
	tst.l			d2
	bne.w			.FastDone
	btst			#31,d0
	beq.w			.FastDone
	move.l			#$7fff0000,d0
	move.l			#$ffffffff,d1
	move.l			#$ffffffff,d2
	bra.w			.FastDone
	.Finite:

	; Ordinary finite nonzero: negative constructs a NaN (ln of a
	; negative number isn't real, same pattern as -Inf above); positive
	; goes through NativeFlogn's atanh series (src/utils/nativemath.asm).
	btst			#31,d0
	beq.s			.Positive
	move.l			#$7fff0000,d0
	move.l			#$ffffffff,d1
	move.l			#$ffffffff,d2
	bra.w			.FastDone
	.Positive:
	jsr				NativeFlogn
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