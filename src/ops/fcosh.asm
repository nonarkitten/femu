;
; fcosh emulation
;
FcoshHandler

	; Debug instruction
	WRITEDEBUG		#.DEBUGOP,INSTRUCTION

	; Increment PC
	INREMENTPC		#$04

	; Get data (extended-format operand, checklist #4)
	GETDATALENGTH	d0
	GETEAVALUE		d0,d1,d2

	; Native cosh(x) = (e^x + e^-x)/2 (checklist #10): no library
	; call, derived from fetox's NativeFexp. cosh is even, so unlike
	; fsinh's self-identical zero/Inf passthrough, cosh(0)=1 (not 0)
	; and cosh(+-Inf)=+Inf regardless of the input's sign -- both
	; constructed explicitly rather than reusing the input's bits.
	bfextu			d0{1:15},d6
	bne.s			.NotZero
	move.l			#$3fff0000,d0
	move.l			#$80000000,d1
	moveq			#0,d2
	bra.w			.FastDone
	.NotZero:

	; Inf/NaN: cosh(+-Inf) = +Inf -- sign forced clear, unlike every
	; other Inf passthrough in this row, which keeps the input's own
	; sign. An actual NaN passes through unchanged, discriminated the
	; same way SETCC itself does (mantissa isn't the clean explicit-
	; bit-only Infinity pattern).
	cmp.l			#32767,d6
	bne.s			.Finite
	cmp.l			#$80000000,d1
	bne.w			.FastDone
	tst.l			d2
	bne.w			.FastDone
	move.l			#$7fff0000,d0
	bra.w			.FastDone
	.Finite:

	; e^x
	move.l			d0,FcoshX
	move.l			d1,FcoshX+4
	move.l			d2,FcoshX+8
	jsr				NativeFexp
	move.l			d0,FcoshEx
	move.l			d1,FcoshEx+4
	move.l			d2,FcoshEx+8

	; e^-x
	move.l			FcoshX,d0
	move.l			FcoshX+4,d1
	move.l			FcoshX+8,d2
	bchg			#31,d0
	jsr				NativeFexp

	; (e^x + e^-x)/2 -- the /2 is a plain exponent decrement. Always
	; positive (both e^x and e^-x are), so -- unlike fsinh's version
	; of this same step -- the sign bit doesn't need preserving, same
	; as NativeFexp/NativeFsqrt's own final bumps.
	move.l			d0,d3
	move.l			d1,d4
	move.l			d2,d5
	move.l			FcoshEx,d0
	move.l			FcoshEx+4,d1
	move.l			FcoshEx+8,d2
	jsr				NativeFadd
	bfextu			d0{1:15},d6
	subq.l			#1,d6
	lsl.l			#8,d6
	lsl.l			#8,d6
	move.l			d6,d0

	.FastDone:
	GETREGISTER		d5
	MOVEDNTOFPN		d5,d0,d1,d2

	; Set condition codes
	SETCC			d0,d1,d2

	; Done
	rts

	; Debug constants
	.DEBUGOP:
	dc.b 			"fcosh %08lx",10,0
	even
FcoshX		dc.l	0,0,0
FcoshEx		dc.l	0,0,0
