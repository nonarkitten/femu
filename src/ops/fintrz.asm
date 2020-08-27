;APS00000000000000000000000000000000000000000000000000000000000000000000000000000000
;
; fintrz emulation
;
; TODO: the IEEEDPFloor is an inaccurate implementation
;       - solve: remove sign bit from D0 and add it later
;

; IN:  D0/D1
; Out: D0/D1
; Trash: D2-D5
FE_FINTRZ	macro
		move.l	d0,d4		;F get upper longword
		and.l	#$7ff00000,d4	;F keep exponent only
		move.l	#$fff00000,d2	;keep sign and exponent by default

		moveq	#0,d3			;lower mask by default
		cmp.l	#$3ff00000+$03400000,d4	;exponent > mantissa bits ?
		bhs.s	.keep			;yes, keep contents (includes INF, NAN)

		moveq	#20,d5			;bits for mantissa shift
		sub.l	#$3ff00000,d4		;exponent < 1 ? 
		blt.s	.zero			;return zero

		lsr.l	d5,d4			;get length of mantissa
		beq.s	.applymask		;mantissa bits empty (=1.0, apply default mask)

		moveq	#-1,d5			;32 bits for inserting
		cmp.b	#20,d4			;more than 20 bits in mantissa ?
		bgt.s	.large_exponent		;yep, should be rare...
		
						;nope, use D4 directly
		bfins	d5,d2{12:d4}		;upper bits to fill in
		bra.s	.applymask
		
.large_exponent:
		moveq	#-1,d2			;upper word is 1
		sub.b	#20,d4			;discount upper word`s bits
		bfins	d5,d3{0:d4}		;lower bits
.applymask:
		and.l	d3,d1
		and.l	d2,d0
		bra.s	.keep
.zero:		and.l	#$80000000,d0		;keep old sign
		moveq	#0,d1			;rest of mantissa = 0
.keep:
		endm


FintrzHandler

	; Debug instruction
	WRITEDEBUG		#.DEBUGOP,INSTRUCTION

	; Increment PC
	INREMENTPC		#$04

	; Get data
	GETDATALENGTH	d0
	GETEAVALUE		d0,d1

	ifd NOMATHLIB
		FE_FINTRZ
	else
		move.l	d0,d4			;F
		and.l	#$80000000,d4		;F remember sign bit
		bclr	#31,d0			;clear sign bit
		; Emulate instruction
		movea.l			MathIeeeDoubBasBase,a6
		jsr				_LVOIEEEDPFloor(a6)
		or.l	d4,d0			;recover sign bit
	endc
	
	; Write results
	GETREGISTER		d5
	MOVEDNTOFPN		d5,d0,d1

	; Set condition codes
	SETCC			d0,d1

	; Done
	rts
	
	; Debug constants
	.DEBUGOP:
	dc.b 			"fintrz %08lx",10,0
	even
