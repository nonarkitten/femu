;
; fatan emulation
;
FatanHandler

	; Debug instruction
	WRITEDEBUG		#.DEBUGOP,INSTRUCTION

	; Increment PC
	INREMENTPC		#$04

	; Get data (extended-format operand, checklist #4)
	GETDATALENGTH	d0
	GETEAVALUE		d0,d1,d2

	; Native atan(x) (checklist #10): no library call, range-reduction
	; + Horner polynomial via NativeFatan (src/utils/nativemath.asm) --
	; the one function in this row needing a genuinely new algorithm
	; rather than a cheap derivation from fexp/flogn/fsincos. atan is
	; odd, so zero (either sign) is self-identical (atan(0)=0). Unlike
	; fsin/fcos/ftan, Inf is NOT NaN here -- atan has real horizontal
	; asymptotes at +-pi/2, so +-Inf maps to a sign-kept +-pi/2
	; (SinCosHalfPi, reused from NativeFsincos). An actual NaN passes
	; through unchanged, discriminated the same way SETCC itself does.
	bfextu			d0{1:15},d6
	beq.w			.FastDone
	cmp.l			#32767,d6
	bne.s			.Finite
	cmp.l			#$80000000,d1
	bne.w			.FastDone
	tst.l			d2
	bne.w			.FastDone
	and.l			#$80000000,d0
	or.l			#$3fff0000,d0
	move.l			#$c90fdaa2,d1
	move.l			#$2168c235,d2
	bra.w			.FastDone
	.Finite:
	jsr				NativeFatan
	.FastDone:
	GETREGISTER		d5
	MOVEDNTOFPN		d5,d0,d1,d2

	; Set condition codes
	SETCC			d0,d1,d2

	; Done
	rts

	; Debug constants
	.DEBUGOP:
	dc.b			"fatan %08lx",10,0
	even
