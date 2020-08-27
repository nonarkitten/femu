;
; fint emulation
;
; TODO: it is known that the library call is not accurate - discuss with Jari
;       whether the NOMATHLIB directive should be cancelled alltogether (bax)
; TODO: Core FPU17 has a bug in FPCR, values cannot be read and/or written -
;       so in the meantime round to nearest is all you get on 080 (bax)
;


FE_FINT		macro

	;--------------------- calculate FINT ---------------------------------------------
	; input   D0/D1 - value to round
	; output  D0/D1 - rounded value (to integer)
	; trash   D0-D5
	; status  68k compliant, no Apollo code, all 4 rounding modes supported
	;----------------------------------------------------------------------------------
;FE_FINT:
	;------------- check pure integer and NaN -----------------------------------------
		move.l	d0,d4		;get upper longword
		beq	.zero		;0 stays 0
		and.l	#$7ff00000,d4	;keep exponent only
		move.l	#$fff00000,d2	;keep sign and exponent by default
	;
		cmp.l	#$3ff00000+$03400000,d4	;exponent > mantissa bits ?
		bhs.w	.keep			;yes, keep contents (includes INF, NAN)

	;---------------- rounding mode decision ------------------------------------------
	ifne	1	;if this is disabled (0), the code performs fintrz
		GETFPCR	d5			;we want the rounding flags (<<4)
		and.b	#FPCR_ROUNDMASK,d5	;$30
		beq.s	.roundnatural		;$00 = natural rounding (default)
		cmp.b	#FPCR_RZ,d5		;RZ is natively supported by the main 
						;operation below
		beq.w	.opoint5done		;$01 = round to zero (will happen anyway, 
						;if no addition takes place below)

		;decision between rounding up or keeping RZ
		; d0          positive   negative
		;-----------------------------------
		;FPCR_CEIL    +0.99999..    +0
		;FPCR_FLOOR   +0         -0.9999..
		;
		bfextu	d0{0:5},d3		;get sign bit to bit 4
		eor.b	d5,d3			;if( (!sign&CEIL)||(sign&FLOOR)) D3=$10
		and.b	#$10,d3			;remove garbage from d3 and keep bit 4 only
		beq	.opoint5done		;if(0) then rely on RZ for positive floor 
						;and negative ceil
						
	;------------- CEIL/FLOOR rounding, add 0.9999999... ------------------------------
	;both can be handled the same way here, because in both cases, it`s a simple add on
	;the mantissa
		moveq	#0,d3			;lower mask by default
		moveq	#20,d5			;bits for mantissa shift
		sub.l	#$3ff00000,d4		;exponent < 1 ? 
		blt.s	.smallmant		;mantissa <$3ff is <=0.5+mantissa

		and.l	d0,d2			;keep exponent + sign
		and.l	#$000fffff,d0
		
		lsr.l	d5,d4			;get length of mantissa
		moveq	#-1,d5
		cmp.b	#20,d4			;more than 20 bits in mantissa ?
		bge.s	.ceil_large_exponent	;yep, should be rare...
		add.b	#12,d4
		lsr.l	d4,d5
		add.l	#$ffffffff,d1
		addx.l	d5,d0
		bra.s	.norm05_finalize	;renormalize d0/d1 if necessary
.ceil_large_exponent: ;more than 20 bits in mantissa for ceil()
		sub.b	#20,d4
		lsr.l	d4,d5			;0.9999999...

		add.l	d5,d1
		addx.l	d3,d0			;
		bra.s	.norm05_finalize	;done, renormalize d0/d1 and then truncate
.smallmant:
		and.l	#$80000000,d0		;anything != 0 in mantissa (implicit first
		or.l	#$3ff00000,d0		;bit) is rounded up to 1
		moveq	#0,d1			;so just write 1.0 and go home
		bra.w	.keep
	;
	;------------- "natural" rounding, add 0.5 before cutting off fraction ------------
	;
.roundnatural:
		moveq	#0,d3			;lower mask by default
		moveq	#20,d5			;bits for mantissa shift
		sub.l  #$3fe00000,d4 ;sub.l	#$3fe00000,d4		;exponent < 1 ? 
		blt.w	.zero			;return zero

		lsr.l	d5,d4			;get length of mantissa
;		beq.s	.norm05			;0.5+x

		and.l	d0,d2			;keep exponent + sign
		and.l	#$000fffff,d0

		moveq	#-1,d3
		add.w	#12,d4
		lsr.l	d4,d3

		cmp.b	#20+12,d4			;more than 20 bits in mantissa ?
		bge.s	.norm05_large_exponent		;yep, should be rare...

		move.l	d0,d5			;F
		or.l	#$00100000,d5		;F implicit to explicit leading 1
		subq.w	#1,d4

		rol.l	d4,d5
		and.b	#1,d5
		or.b	d5,d1

		moveq	#-1,d5

		add.l	d5,d1
		addx.l	d3,d0
.norm05_finalize:
		cmp.l	#$00100000,d0		;first mantissa bit overflow ?
		blt.s	.opoint5noovl

		and.l	#$000fffff,d0	;shift mantissa right
		lsr.l	#1,d0		;
		roxr.l	#1,d1		;
		add.l	#$00100000,d2	;exponent + 1
.opoint5noovl:
		or.l	d2,d0
		moveq	#0,d3
		bra.s	.opoint5done

.norm05_large_exponent:		;should be rare...
		sub.w	#32,d4
		cmp.b	#32,d4
		beq.s	.norm05_largest_exponent	;largest valid exponent, 0.5 is 1 bit to the right

		moveq	#-1,d3
		lsr.l	d4,d3
		;bset	#0,d3

		; check for rounding up: when the number is even, round down at exactly
		; 0.5 otherwise up
		move.l	d1,d5	   ;lower part of mantissa
		lsr.l	#1,d5	   ;make space for one more bit from upper part
		bfins	d0,d5{0:1} ;

		rol.l	d4,d5
		and.b	#1,d5
		or.b	d5,d1

		 add.l	d3,d1
		moveq	#0,d3
		addx.l	d3,d0			;
		bra.s	.norm05_finalize
.norm05_largest_exponent:	;largest valid exponent, 0.5 is 1 bit to the right
		bfextu	d1{30:1},d3
		 add.l	d3,d1
		moveq	#0,d3
		addx.l	d3,d0			;
		bra.s	.norm05_finalize
.norm05:	
		and.l	#$80000000,d0
		or.l	#$3ff00000,d0
		moveq	#0,d1
;		bra	.opoint5done
.opoint5done:

	endc	;ifne 1

	;----------------------------------------------------------------------------------
	;get D4 (again), exponent might have changed
	;
		moveq	#0,d3
		move.l	#$fff00000,d2	;keep sign and exponent by default (restore D2)
		move.l	d0,d4		;F get upper longword
		and.l	#$7ff00000,d4	;F keep exponent only
	;------------- calculate mask for mantissa ----------------------------------------
		moveq	#20,d5			;bits for mantissa shift
		sub.l	#$3ff00000,d4		;exponent < 1 ? 
		blt.s	.zero			;return zero

		lsr.l	d5,d4			;get length of mantissa
		beq.s	.applymask		;mantissa bits empty (=1.0, apply default mask)

		moveq	#-1,d5			;32 bits for inserting
		cmp.b	#20,d4			;more than 20 bits in mantissa ?
		bgt.s	.large_exponent		;yep, should be rare...

		bfins	d5,d2{12:d4}		;upper bits to fill in for mask
		bra.s	.applymask		
.noshift:
		or.l	d1,d0			;restore exponent
		bra.s	.applymask
	;------------- large exponent, only lower 32 Bit of Mantissa relevant -------------
.large_exponent:
		moveq	#-1,d2			;upper word is 1
		sub.b	#20,d4			;discount upper word`s bits
		bfins	d5,d3{0:d4}		;lower bits
	;------------- apply mask on mantissa ---------------------------------------------
.applymask:
		and.l	d3,d1
		and.l	d2,d0
		bra.s	.keep
	;------------- value was zero or is zero after cutting off fraction ---------------
.zero:		
		;moveq	#0,d0
		and.l	#$80000000,d0		;keep old sign
		moveq	#0,d1			;rest of mantissa = 0
.keep:

	;-------------------------- DONE: results in D0/D1  -------------------------------
		endm


FintHandler

	; Debug instruction
	WRITEDEBUG		#.DEBUGOP,INSTRUCTION

	; Increment PC
	INREMENTPC		#$04
	
	; Get data
	GETDATALENGTH	d0
	GETEAVALUE		d0,d1

	ifd NOMATHLIB
		FE_FINT
	else
		move.l			#$3fe00000,d2
		move.l			#$00000000,d3
		; Emulate instruction
		movea.l			MathIeeeDoubBasBase,a6
		jsr				_LVOIEEEDPAdd(a6)
		jsr				_LVOIEEEDPFloor(a6)
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
	dc.b 			"fint %08lx",10,0
	even
