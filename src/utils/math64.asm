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
; Converts an extended-format (checklist #4) value into a 'fake' 96-bit
; integer -- same ordering-preserving trick as FAKE64, just one limb
; wider (sign+exponent+reserved, mantissa hi, mantissa lo).
;
; INPUTS
;	\1 -- Sign(1):exponent(15):reserved(16).
;	\2 -- Mantissa bits 63-32.
;	\3 -- Mantissa bits 31-0.
;
; RESULT
;	\1 -- Sign(1):exponent(15):reserved(16).
;	\2 -- Mantissa bits 63-32.
;	\3 -- Mantissa bits 31-0.
;
FAKE96 macro
	btst			#31,\1
	beq.s			.\@Ok
	eor.l			#$7FFFFFFF,\1
	eor.l			#$FFFFFFFF,\2
	eor.l			#$FFFFFFFF,\3
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
; Checks if an extended-format (checklist #4) value is INF or NAN. The
; reserved word (low 16 bits of \1) is always 0, so unlike ISNAN's
; double-format range check (which had to account for fraction bits
; sharing the same register as the exponent), the exponent-all-ones
; pattern has exactly one bit-exact value per sign -- a plain equality
; check, non-destructive, no scratch register needed.
;
; INPUTS
;	\1 -- Sign(1):exponent(15):reserved(16)
;   \2 -- Branch if INF or NAN
ISNAN96 macro
	cmp.l			#$7fff0000,\1
	beq.w			\2
	cmp.l			#$ffff0000,\1
	beq.w			\2
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
; Performs 96 bit sub -- same low-to-high subx chain as SUB64, one limb
; wider, for extended-format (checklist #4) fcmp.
;
; INPUTS
;	\1 -- High bits.
;	\2 -- Mid bits.
;	\3 -- Low bits.
;	\4 -- High bits.
;	\5 -- Mid bits.
;	\6 -- Low bits.
;
; RESULT
;	\4 -- High bits of (\4:\5:\6) - (\1:\2:\3).
;	\5 -- Mid bits.
;	\6 -- Low bits.
;
SUB96 macro
	sub.l			\3,\6
	subx.l			\2,\5
	subx.l			\1,\4
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
; Performs an unsigned 64x64 -> 128 bit multiply.
;
; INPUTS
;	\1 -- A, high 32 bits.
;	\2 -- A, low 32 bits.
;	\3 -- B, high 32 bits.
;	\4 -- B, low 32 bits.
;	\5 -- Scratch data register.
;	\6 -- Scratch data register.
;
; RESULT
;	\1 -- Bits 127-96 of A*B (most significant).
;	\2 -- Bits 95-64.
;	\3 -- Bits 63-32.
;	\4 -- Bits 31-0 (least significant).
;
; \1-\4 are read once each (stashed to MulOperands, since mulu.l's second
; operand can be a memory location) and only written at the very end, so
; it's safe for the result to reuse the same registers as the inputs.
; Standard schoolbook 64x64 multiply via four 32x32->64 hardware
; multiplies (mulu.l, 68020+): A*B = Ahi*Bhi*2^64 + (Ahi*Blo+Alo*Bhi)*2^32
; + Alo*Blo. Each partial product is added into the 128-bit accumulator
; (kept in \1-\4 throughout) with carry propagated by hand, since ADDX
; only accepts Dn,Dn or -(An),-(An) operand pairs -- not a register and
; an absolute memory location -- so a plain ADD (which does allow a
; memory destination) plus a conditional ADDQ stands in for it. Given
; both factors here are at most 53-bit mantissas (so \1/\3 only ever
; hold values below 2^21), no more than one word of carry ever needs to
; propagate past the pair an individual partial product lands in.
;
MUL64 macro
	move.l		\1,MulOperands
	move.l		\2,MulOperands+4
	move.l		\3,MulOperands+8
	move.l		\4,MulOperands+12

	moveq		#0,\1
	moveq		#0,\2
	moveq		#0,\3
	moveq		#0,\4

	; Alo*Blo -> bits 63:0 of the product
	move.l		MulOperands+4,\5
	mulu.l		MulOperands+12,\6:\5
	add.l		\5,\4
	addx.l		\6,\3
	bcc.s		.\@T0Ok
	addq.l		#1,\2
	.\@T0Ok:

	; Ahi*Blo -> bits 95:32
	move.l		MulOperands,\5
	mulu.l		MulOperands+12,\6:\5
	add.l		\5,\3
	addx.l		\6,\2
	bcc.s		.\@T1Ok
	addq.l		#1,\1
	.\@T1Ok:

	; Alo*Bhi -> bits 95:32
	move.l		MulOperands+4,\5
	mulu.l		MulOperands+8,\6:\5
	add.l		\5,\3
	addx.l		\6,\2
	bcc.s		.\@T2Ok
	addq.l		#1,\1
	.\@T2Ok:

	; Ahi*Bhi -> bits 127:64
	move.l		MulOperands,\5
	mulu.l		MulOperands+8,\6:\5
	add.l		\5,\2
	addx.l		\6,\1
endm
MulOperands	dc.l	0,0,0,0


;
; Performs an unsigned 64-bit division via \7 iterations of restoring
; binary division (shift both R and Q left, try R -= V, keep the
; subtraction and set the new quotient bit if it didn't borrow, else
; undo it).
;
; INPUTS
;	\1:\2 -- R, the dividend, high:low. Must be < V.
;	\3:\4 -- V, the divisor, high:low. Must be nonzero.
;	\5:\6 -- Q, the quotient accumulator. Must be zeroed by the caller.
;	\7 -- Iteration count (immediate, 1-255).
;
; RESULT
;	\1:\2 -- The final remainder. Nonzero means the division was inexact
;	         (needed for correct rounding).
;	\5:\6 -- The quotient, \7 significant bits, right-justified.
;
; This is not the fast version -- seeding it from a hardware 32-bit
; divide instead of one-bit-at-a-time steps is a fair candidate for a
; later, separately measured idea (see BENCHMARK.md). Uses DivCounter
; (1 byte of scratch memory) as the loop counter so every data register
; stays free for R/V/Q.
;
; The R<V invariant bounds 2R to strictly less than 2V, which stayed
; safely inside a 64-bit register pair back when this only served
; 53-bit double mantissas (V < 2^53, so 2R < 2^54 -- 10 bits of
; headroom). Checklist #4's full-width 64-bit extended mantissas have
; none: V can be anywhere in [2^63,2^64), so 2R can genuinely need a
; 65th bit that \1:\2 cannot represent on its own. Rather than widen the
; accumulator, this relies on the fact that IF the doubling overflows
; (the bit shifted off \1's top is a real, not phantom, 65th bit), the
; true (65-bit) remainder is unconditionally >= any 64-bit V -- so that
; iteration's quotient bit is 1 without needing to test it, and the
; ordinary 64-bit subtraction that follows (\1:\2 -= \3:\4, discarding
; whatever borrow it reports) already lands on the exact correct
; remainder: true_2R - V = 2^64 + (2R mod 2^64) - V, and since the
; result is proven < V < 2^64, that's exactly (2R mod 2^64) - V computed
; modulo 2^64, i.e. plain wraparound subtraction, no correction needed.
;
DIV64 macro
	move.b		#\7,DivCounter
	.\@Loop:
	lsl.l		#1,\2
	roxl.l		#1,\1
	bcs.s		.\@Overflowed

	lsl.l		#1,\6
	roxl.l		#1,\5
	sub.l		\4,\2
	subx.l		\3,\1
	bcc.s		.\@Bit1
	add.l		\4,\2
	addx.l		\3,\1
	bra.s		.\@Next
	.\@Bit1:
	addq.l		#1,\6
	bra.s		.\@Next

	.\@Overflowed:
	lsl.l		#1,\6
	roxl.l		#1,\5
	sub.l		\4,\2
	subx.l		\3,\1
	addq.l		#1,\6

	.\@Next:
	subq.b		#1,DivCounter
	bne.s		.\@Loop
endm
DivCounter	dc.b	0
			even


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
