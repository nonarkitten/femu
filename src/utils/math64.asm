;
; Converts double into 'fake' 64-bit integer
;
; INPUTS
;	\1 -- High bits.
;	\2 -- Low bits.
;
; RESULT
;	\1 -- High bits.
;	\2 -- Low bits.
;
FAKE64 macro
	btst			#31,\1
	beq.s			.\@Ok
	eor.l			#$7FFFFFFF,\1
	eor.l			#$FFFFFFFF,\2
	.\@Ok:
endm

;
; Checks if value is INF or NAN
;
; INPUTS
;	\1 -- High bits
;   \2 -- Branch if INF or NAN
ISNAN macro
	cmp.l			#$7FEFFFFF,\1
	bgt.s			\2
	cmp.l			#$FFF00000,\1
	bls.s			\2
endm

;
; Performs 64 bit add.
; 
; INPUTS
;	\1 -- High bits.
;	\2 -- Low bits.
;	\3 -- High bits.
;	\4 -- Low bits.
;
; RESULT
;	\1 -- High bits.
;	\2 -- Low bits.
;
ADD64 macro
	add.l			\2,\4
	addx.l			\1,\3
endm


;
; Performs 64 bit sub.
; 
; INPUTS
;	\1 -- High bits.
;	\2 -- Low bits.
;	\3 -- High bits.
;	\4 -- Low bits.
;
; RESULT
;	\1 -- High bits.
;	\2 -- Low bits.
;
SUB64 macro
	sub.l			\2,\4
	subx.l			\1,\3
endm


;
; Performs 64 bit neg.
; 
; INPUTS
;	\1 -- High bits.
;	\2 -- Low bits.
;
; RESULT
;	\1 -- High bits.
;	\2 -- Low bits.
;
NEG64 macro
	neg.l			\2
	negx.l			\1
endm


;
; Performs 64 bit abs.
; 
; INPUTS
;	\1 -- High bits.
;	\2 -- Low bits.
;
; RESULT
;	\1 -- High bits.
;	\2 -- Low bits.
;
ABS64 macro

	;TODO: d6 stuff is WIP, required for FE_FADD implementation, but should not be here!
	moveq			 #0,d6
	
	btst			#31,\1
	beq.s			.\@Ok
	NEG64			\1,\2
	
	moveq			 #1,d6
	
	.\@Ok:
endm


;
; Performs 64 bit lsl. 
; 
; INPUTS
;	\1 -- Shift bits.
;	\2 -- High bits.
;	\3 -- Low bits.
;
; RESULT
;	\1 -- High bits.
;	\2 -- Low bits.
;
; TODO: use LSL.Q for 080v3
;
LSL64 macro

	cmp.b		#32,\1
	blt.s		.\@ShiftLess
	
	.\@ShiftMore:
	move.l		\3,\2
	move.l		#0,\3
	subi.l		#32,\1
	lsl.l		\1,\2
	addi.l		#32,\1
	bra.s		.\@ShiftOk
	
	.\@ShiftLess:
	LSL64L		\1,\2,\3
	
	.\@ShiftOk:

endm


;
; Performs 64 bit lsl. 
; Shifts 32 bits at max. 
; 
; INPUTS
;	\1 -- Shift bits.
;	\2 -- High bits.
;	\3 -- Low bits.
;
; RESULT
;	\1 -- High bits.
;	\2 -- Low bits.
;
; TODO: use LSL.Q for 080v3
; 	19:01 < BigGun> LSL.Q
; 	19:01 < BigGun> example : LSL.Q D0,D1,D2
; 	19:01 < BigGun> shifts D1, (all 64bit)
; 	19:02 < BigGun> by count in D0
; 	19:02 < BigGun> stores result in D2
; 	19:02 < BigGun> AMMX ID = $38
;
LSL64L macro
	rol.l		\1,\3
	bfins		\3,\2{0:\1}
	rol.l		\1,\2
	lsr.l		\1,\3
	lsl.l		\1,\3
endm


;
; Performs 64 bit lsr. 
; 
; INPUTS
;	\1 -- Shift bits.
;	\2 -- High bits.
;	\3 -- Low bits.
;
; RESULT
;	\1 -- High bits.
;	\2 -- Low bits.
;
; TODO: use LSL.Q for 080v3
;
LSR64 macro

	cmp.b		#32,\1
	blt.s		.\@ShiftLess
	
	.\@ShiftMore:
	move.l		\2,\3
	move.l		#0,\2
	subi.l		#32,\1
	lsr.l		\1,\3
	addi.l		#32,\1
	bra.s		.\@ShiftOk
	
	.\@ShiftLess:
	LSR64L		\1,\2,\3
	
	.\@ShiftOk:

endm


;
; Performs 64 bit lsr. 
; Shifts 32 bits at max.
; 
; INPUTS
;	\1 -- Shift bits.
;	\2 -- High bits.
;	\3 -- Low bits.
;
; RESULT
;	\1 -- High bits.
;	\2 -- Low bits.
;
; TODO: use LSL.Q for 080v3
;
LSR64L macro
	lsr.l		\1,\3
	bfins		\2,\3{0:\1}
	lsr.l		\1,\2
endm
