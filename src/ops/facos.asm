;
; facos emulation
;
FacosHandler

	; Debug instruction
	WRITEDEBUG		#.DEBUGOP,INSTRUCTION

	; Increment PC
	INREMENTPC		#$04

	; Get data (extended-format operand, checklist #4)
	GETDATALENGTH	d0
	GETEAVALUE		d0,d1,d2

	; Native acos(x) = pi/2 - asin(x) (checklist #10): no library call,
	; no new algorithm either -- reuses NativeFasin (src/utils/
	; nativemath.asm), the same "derive from an already-landed piece"
	; move as ftan.asm deriving from NativeFsincos. Unlike fasin, acos
	; has no zero-is-self-identical shortcut (acos is neither odd nor
	; even) -- every case from here needs an actual result, so the
	; ladder below covers all of them: 0 -> pi/2; +1 -> 0; -1 -> pi
	; (an exact exponent-bumped double of pi/2, same bit trick used
	; throughout this row rather than a second independently-rounded
	; constant); |x|>1 (finite) and +-Inf both construct a NaN (out of
	; domain); an actual NaN passes through unchanged.
	bfextu			d0{1:15},d6
	bne.s			.NotZero
	move.l			#$3fff0000,d0
	move.l			#$c90fdaa2,d1
	move.l			#$2168c235,d2
	bra.w			.FastDone
	.NotZero:

	; Inf/NaN: Inf's magnitude is "> 1" same as any out-of-domain
	; finite value, so it falls through to the NaN-construction case
	; below once discriminated from an actual NaN (which must pass
	; through unchanged instead).
	cmp.l			#32767,d6
	bne.s			.CheckRange
	cmp.l			#$80000000,d1
	bne.w			.FastDone
	tst.l			d2
	bne.w			.FastDone
	bra.w			.OutOfDomain
	.CheckRange:

	; |x| vs 1.0 -- a plain 3-word unsigned lexicographic compare
	; against 1.0's known bit pattern, valid because both operands are
	; positive, finite, normalized extended values (same reasoning
	; NativeFatan's own range-reduction compares rely on). d3:d4:d5
	; holds |x|'s word0/mantissa (d0's sign bit cleared) for the
	; compare; the real sign stays in d0 to tell +1 from -1 below.
	move.l			d0,d3
	and.l			#$7fffffff,d3
	move.l			d1,d4
	move.l			d2,d5
	cmp.l			#$3fff0000,d3
	bhi.w			.OutOfDomain
	blo.w			.Finite
	cmp.l			#$80000000,d4
	bhi.w			.OutOfDomain
	blo.w			.Finite
	cmp.l			#$00000000,d5
	bhi.w			.OutOfDomain
	bne.w			.Finite

	; |x| == 1.0 exactly -- acos(+1)=0, acos(-1)=pi.
	tst.l			d0
	bmi.s			.MinusOne
	moveq			#0,d0
	moveq			#0,d1
	moveq			#0,d2
	bra.w			.FastDone
	.MinusOne:
	move.l			#$40000000,d0
	move.l			#$c90fdaa2,d1
	move.l			#$2168c235,d2
	bra.w			.FastDone

	.OutOfDomain:
	move.l			#$7fff0000,d0
	move.l			#$ffffffff,d1
	move.l			#$ffffffff,d2
	bra.w			.FastDone

	.Finite:
	jsr				NativeFasin
	move.l			d0,d3
	move.l			d1,d4
	move.l			d2,d5
	move.l			#$3fff0000,d0
	move.l			#$c90fdaa2,d1
	move.l			#$2168c235,d2
	jsr				NativeFsub
	.FastDone:
	GETREGISTER		d5
	MOVEDNTOFPN		d5,d0,d1,d2

	; Set condition codes
	SETCC			d0,d1,d2

	; Done
	rts

	; Debug constants
	.DEBUGOP:
	dc.b			"facos %08lx",10,0
	even
