;
; fasin emulation
;
FasinHandler

	; Debug instruction
	WRITEDEBUG		#.DEBUGOP,INSTRUCTION

	; Increment PC
	INREMENTPC		#$04

	; Get data (extended-format operand, checklist #4)
	GETDATALENGTH	d0
	GETEAVALUE		d0,d1,d2

	; Native asin(x) = atan(x/sqrt(1-x^2)) (checklist #10): no library
	; call, no new algorithm either -- NativeFasin (src/utils/
	; nativemath.asm) composes it entirely from already-landed pieces.
	; asin is odd, so zero (either sign) is self-identical (asin(0)=0).
	; |x|==1 is in-domain but NativeFasin can't take it (its own 1-x^2
	; would be exactly zero, dividing by a zero sqrt) -- handled here
	; instead as the exact, trivial result sign-kept +-pi/2 (reusing
	; NativeFsincos's own SinCosHalfPi). |x|>1 (finite) is out of
	; asin's domain -- constructs a NaN, same as any host asin(). An
	; actual NaN passes through unchanged.
	bfextu			d0{1:15},d6
	beq.w			.FastDone

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
	; compare; the real sign stays in d0 for the later sign-kept
	; +-pi/2 construction.
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

	; |x| == 1.0 exactly -- sign-kept +-pi/2, no computation needed.
	and.l			#$80000000,d0
	or.l			#$3fff0000,d0
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
	.FastDone:
	GETREGISTER		d5
	MOVEDNTOFPN		d5,d0,d1,d2

	; Set condition codes
	SETCC			d0,d1,d2

	; Done
	rts

	; Debug constants
	.DEBUGOP:
	dc.b			"fasin %08lx",10,0
	even
