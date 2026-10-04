;
; ftan emulation
;
FtanHandler

	; Debug instruction
	WRITEDEBUG		#.DEBUGOP,INSTRUCTION

	; Increment PC
	INREMENTPC		#$04

	; Get data (extended-format operand, checklist #4)
	GETDATALENGTH	d0
	GETEAVALUE		d0,d1,d2

	; Native tan(x) = sin(x)/cos(x) (checklist #10): no library call,
	; derived from fsin/fcos's own NativeFsincos -- which conveniently
	; already returns sin(x) in d0:d1:d2 and cos(x) in d3:d4:d5, the
	; exact dst/src layout NativeFdiv expects, so no scratch memory is
	; needed at all. tan is odd, so zero (either sign) is self-
	; identical (tan(0)=0). Inf is NaN, same reasoning as fsin/fcos's
	; own Inf case (the function has no limit as x->+-Inf); an actual
	; NaN passes through unchanged. A pole (cos(x)==0 exactly) isn't
	; special-cased -- NativeFdiv's own zero-divisor handling already
	; produces the correct signed Infinity, and in practice a pole is
	; never landed on exactly anyway (pi/2 itself isn't representable),
	; same as any host libm's tan().
	bfextu			d0{1:15},d6
	beq.w			.FastDone
	cmp.l			#32767,d6
	bne.s			.Finite
	cmp.l			#$80000000,d1
	bne.w			.FastDone
	tst.l			d2
	bne.w			.FastDone
	move.l			#$7fff0000,d0
	move.l			#$ffffffff,d1
	move.l			#$ffffffff,d2
	bra.w			.FastDone
	.Finite:
	jsr				NativeFsincos
	jsr				NativeFdiv
	.FastDone:
	GETREGISTER		d5
	MOVEDNTOFPN		d5,d0,d1,d2

	; Set condition codes
	SETCC			d0,d1,d2

	; Done
	rts

	; Debug constants
	.DEBUGOP:
	dc.b 			"ftan %08lx",10,0
	even
