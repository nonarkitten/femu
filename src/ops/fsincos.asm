;
; fsincos emulation
;
FsincosHandler

	; Debug instruction
	WRITEDEBUG		#.DEBUGOP,INSTRUCTION

	; Increment PC
	INREMENTPC		#$04

	; Get data (extended-format operand, checklist #4)
	GETDATALENGTH	d0
	GETEAVALUE		d0,d1,d2

	; Native sin(x)+cos(x) together (checklist #10): no library call,
	; one call into fsin/fcos's own NativeFsincos instead of two. The
	; special-case ladder matches fsin.asm/fcos.asm's own (zero self-
	; identical for sin, constructed 1.0 for cos; Inf is NaN for both,
	; same reasoning as fsin/fcos's own Inf case; an actual NaN passes
	; through unchanged to both), just producing both results from one
	; branch instead of two separate ladders.
	bfextu			d0{1:15},d6
	bne.s			.NotZero
	move.l			d0,FsincosSin
	move.l			d1,FsincosSin+4
	move.l			d2,FsincosSin+8
	move.l			#$3fff0000,FsincosCos
	move.l			#$80000000,FsincosCos+4
	moveq			#0,d6
	move.l			d6,FsincosCos+8
	bra.w			.WriteBack
	.NotZero:
	cmp.l			#32767,d6
	bne.s			.Finite
	cmp.l			#$80000000,d1
	bne.s			.GotNan
	tst.l			d2
	bne.s			.GotNan
	move.l			#$7fff0000,FsincosSin
	move.l			#$ffffffff,FsincosSin+4
	move.l			#$ffffffff,FsincosSin+8
	move.l			#$7fff0000,FsincosCos
	move.l			#$ffffffff,FsincosCos+4
	move.l			#$ffffffff,FsincosCos+8
	bra.w			.WriteBack
	.GotNan:
	move.l			d0,FsincosSin
	move.l			d1,FsincosSin+4
	move.l			d2,FsincosSin+8
	move.l			d0,FsincosCos
	move.l			d1,FsincosCos+4
	move.l			d2,FsincosCos+8
	bra.w			.WriteBack
	.Finite:
	jsr				NativeFsincos
	move.l			d0,FsincosSin
	move.l			d1,FsincosSin+4
	move.l			d2,FsincosSin+8
	move.l			d3,FsincosCos
	move.l			d4,FsincosCos+4
	move.l			d5,FsincosCos+8
	.WriteBack:

	; Write results. The real 68881's FSINCOS puts sin in the normal
	; destination register field and cos in the separate "FPc" field
	; at bit 29 of the extension word -- same two-register split the
	; old library-based version of this handler already used, kept
	; as-is here (GETREGISTER's \2 offset, MOVEDNTOFPN's d5 reuse for
	; the second index). Condition codes end up reflecting cos (the
	; last value loaded into d0:d1:d2), matching that old behaviour.
	move.l			FsincosSin,d0
	move.l			FsincosSin+4,d1
	move.l			FsincosSin+8,d2
	GETREGISTER		d5
	MOVEDNTOFPN		d5,d0,d1,d2
	move.l			FsincosCos,d0
	move.l			FsincosCos+4,d1
	move.l			FsincosCos+8,d2
	GETREGISTER		d5,29
	MOVEDNTOFPN		d5,d0,d1,d2

	; Set condition codes
	SETCC			d0,d1,d2

	; Done
	rts

	; Debug constants
	.DEBUGOP:
	dc.b 			"fsincos %08lx",10,0
	even
FsincosSin	dc.l	0,0,0
FsincosCos	dc.l	0,0,0
