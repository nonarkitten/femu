;
; fsinh emulation
;
FsinhHandler

	; Debug instruction
	WRITEDEBUG		#.DEBUGOP,INSTRUCTION

	; Increment PC
	INREMENTPC		#$04

	; Get data (extended-format operand, checklist #4)
	GETDATALENGTH	d0
	GETEAVALUE		d0,d1,d2

	; Native sinh(x) = (e^x - e^-x)/2 (checklist #10): no library call,
	; derived directly from fetox's NativeFexp rather than needing its
	; own algorithm. sinh is odd, so zero (either sign) and Inf (either
	; sign) are both exactly self-identical (sinh(0)=0, sinh(+-Inf)=
	; +-Inf) -- same bits straight back out, no computation. An actual
	; NaN is ALSO self-identical here (same bits in, same bits out is
	; correct for a NaN regardless of function), so the exponent-field-
	; all-ones check below covers Inf and NaN together with one branch
	; -- unlike fetox/fsqrt/flogn's own ladders, nothing here needs to
	; discriminate between the two.
	bfextu			d0{1:15},d6
	beq.w			.FastDone
	cmp.l			#32767,d6
	beq.w			.FastDone

	; e^x
	move.l			d0,FsinhX
	move.l			d1,FsinhX+4
	move.l			d2,FsinhX+8
	jsr				NativeFexp
	move.l			d0,FsinhEx
	move.l			d1,FsinhEx+4
	move.l			d2,FsinhEx+8

	; e^-x
	move.l			FsinhX,d0
	move.l			FsinhX+4,d1
	move.l			FsinhX+8,d2
	bchg			#31,d0
	jsr				NativeFexp

	; (e^x - e^-x)/2 -- the /2 is a plain exponent decrement (inverse
	; of the exponent-bump technique #10's other rows use), but unlike
	; those rows' always-positive results, sinh's sign must be kept --
	; extracted via bfextu/reinserted via bfins (the bit0-right-
	; justified convention those two actually agree on; see
	; FE_FADD's own MainBody top for the same pairing, and
	; nativemath.asm's header comment for why the OTHER convention,
	; "d6 = sign & $80000000", does NOT pair safely with bfins).
	move.l			d0,d3
	move.l			d1,d4
	move.l			d2,d5
	move.l			FsinhEx,d0
	move.l			FsinhEx+4,d1
	move.l			FsinhEx+8,d2
	jsr				NativeFsub
	bfextu			d0{0:1},d6
	bfextu			d0{1:15},d0
	subq.l			#1,d0
	lsl.l			#8,d0
	lsl.l			#8,d0
	bfins			d6,d0{0:1}

	.FastDone:
	GETREGISTER		d5
	MOVEDNTOFPN		d5,d0,d1,d2

	; Set condition codes
	SETCC			d0,d1,d2

	; Done
	rts

	; Debug constants
	.DEBUGOP:
	dc.b 			"fsinh %08lx",10,0
	even
FsinhX		dc.l	0,0,0
FsinhEx		dc.l	0,0,0
