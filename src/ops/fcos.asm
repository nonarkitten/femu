;
; fcos emulation
;
FcosHandler

	; Debug instruction
	WRITEDEBUG		#.DEBUGOP,INSTRUCTION

	; Increment PC
	INREMENTPC		#$04

	; Get data (extended-format operand, checklist #4)
	GETDATALENGTH	d0
	GETEAVALUE		d0,d1,d2

	; Native cos(x) (checklist #10): no library call. cos is even, so
	; cos(0)=1 (NOT self-identical, unlike fsin's zero fast path) is
	; constructed explicitly. cos(+-Inf) is undefined (same reasoning
	; as fsin.asm's own Inf case -> NaN); an actual NaN passes through
	; unchanged. Everything else goes through NativeFsincos
	; (src/utils/nativemath.asm), shared with fsin.asm -- cos(x) comes
	; back in d3:d4:d5, sin(x) in d0:d1:d2 is discarded here.
	bfextu			d0{1:15},d6
	bne.s			.NotZero
	move.l			#$3fff0000,d0
	move.l			#$80000000,d1
	moveq			#0,d2
	bra.w			.FastDone
	.NotZero:
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
	move.l			d3,d0
	move.l			d4,d1
	move.l			d5,d2
	.FastDone:
	GETREGISTER		d5
	MOVEDNTOFPN		d5,d0,d1,d2

	; Set condition codes
	SETCC			d0,d1,d2

	; Done
	rts

	; Debug constants
	.DEBUGOP:
	dc.b 			"fcos %08lx",10,0
	even
