;
; ftanh emulation
;
FtanhHandler

	; Debug instruction
	WRITEDEBUG		#.DEBUGOP,INSTRUCTION

	; Increment PC
	INREMENTPC		#$04

	; Get data (extended-format operand, checklist #4)
	GETDATALENGTH	d0
	GETEAVALUE		d0,d1,d2

	; Native tanh(x) = (e^x-e^-x)/(e^x+e^-x) (checklist #10): no
	; library call, derived from fetox's NativeFexp -- the /2 implicit
	; in sinh(x)/cosh(x)'s own definitions cancels in the ratio, so it
	; never needs computing here. tanh is odd, so zero (either sign)
	; is self-identical (tanh(0)=0) just like fsinh's.
	bfextu			d0{1:15},d6
	beq.w			.FastDone

	; Inf/NaN: tanh(+-Inf) = +-1 -- sign kept, magnitude replaced
	; (unlike fsinh's fully self-identical Inf passthrough, since
	; tanh's horizontal asymptote is +-1, not +-Inf). An actual NaN
	; passes through unchanged, discriminated the same way SETCC
	; itself does.
	cmp.l			#32767,d6
	bne.s			.Finite
	cmp.l			#$80000000,d1
	bne.w			.FastDone
	tst.l			d2
	bne.w			.FastDone
	and.l			#$80000000,d0
	or.l			#$3fff0000,d0
	move.l			#$80000000,d1
	moveq			#0,d2
	bra.w			.FastDone
	.Finite:

	; e^x
	move.l			d0,FtanhX
	move.l			d1,FtanhX+4
	move.l			d2,FtanhX+8
	jsr				NativeFexp
	move.l			d0,FtanhEx
	move.l			d1,FtanhEx+4
	move.l			d2,FtanhEx+8

	; e^-x
	move.l			FtanhX,d0
	move.l			FtanhX+4,d1
	move.l			FtanhX+8,d2
	bchg			#31,d0
	jsr				NativeFexp
	move.l			d0,FtanhNegEx
	move.l			d1,FtanhNegEx+4
	move.l			d2,FtanhNegEx+8

	; numerator = e^x - e^-x
	move.l			FtanhNegEx,d3
	move.l			FtanhNegEx+4,d4
	move.l			FtanhNegEx+8,d5
	move.l			FtanhEx,d0
	move.l			FtanhEx+4,d1
	move.l			FtanhEx+8,d2
	jsr				NativeFsub
	move.l			d0,FtanhNum
	move.l			d1,FtanhNum+4
	move.l			d2,FtanhNum+8

	; denominator = e^x + e^-x
	move.l			FtanhNegEx,d3
	move.l			FtanhNegEx+4,d4
	move.l			FtanhNegEx+8,d5
	move.l			FtanhEx,d0
	move.l			FtanhEx+4,d1
	move.l			FtanhEx+8,d2
	jsr				NativeFadd

	; tanh(x) = numerator/denominator
	move.l			d0,d3
	move.l			d1,d4
	move.l			d2,d5
	move.l			FtanhNum,d0
	move.l			FtanhNum+4,d1
	move.l			FtanhNum+8,d2
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
	dc.b 			"ftanh %08lx",10,0
	even
FtanhX		dc.l	0,0,0
FtanhEx		dc.l	0,0,0
FtanhNegEx	dc.l	0,0,0
FtanhNum	dc.l	0,0,0
