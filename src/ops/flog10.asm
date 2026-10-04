;
; flog10 emulation
;
flog10Handler

	; Debug instruction
	WRITEDEBUG		#.DEBUGOP,INSTRUCTION

	; Increment PC
	INREMENTPC		#$04

	; Get data (extended-format operand, checklist #4)
	GETDATALENGTH	d0
	GETEAVALUE		d0,d1,d2

	; Native general case (checklist #10): log10(x) = ln(x)/ln(10) --
	; no library call. Special-case ladder duplicated from flogn.asm
	; (see flog2.asm's copy of the same comment for why duplicated, not
	; shared): zero (either sign) -> -Inf (pole error); +Inf passes
	; through unchanged; -Inf and any finite negative x -> NaN; an
	; actual NaN passes through unchanged. Only the ordinary positive
	; finite case differs, needing the extra multiply by 1/ln(10)
	; (ExpInvLn10, src/utils/nativemath.asm) after NativeFlogn.
	bfextu			d0{1:15},d6
	bne.s			.NotZero
	move.l			#$ffff0000,d0
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
	btst			#31,d0
	beq.w			.FastDone
	move.l			#$7fff0000,d0
	move.l			#$ffffffff,d1
	move.l			#$ffffffff,d2
	bra.w			.FastDone
	.Finite:
	btst			#31,d0
	beq.s			.Positive
	move.l			#$7fff0000,d0
	move.l			#$ffffffff,d1
	move.l			#$ffffffff,d2
	bra.w			.FastDone
	.Positive:
	jsr				NativeFlogn
	move.l			d0,d3
	move.l			d1,d4
	move.l			d2,d5
	lea.l			ExpInvLn10,a0
	movem.l			(a0),d0/d1/d2
	jsr				NativeFmul
	.FastDone:
	GETREGISTER		d5
	MOVEDNTOFPN		d5,d0,d1,d2

	; Set condition codes
	SETCC			d0,d1,d2

	; Done
	rts

	; Debug constants
	.DEBUGOP:
	dc.b 			"flog10 %08lx",10,0
	even
