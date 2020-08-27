;
; Aligns exponents of two doubles.
; 
; INPUTS
;	\1 -- Exponent.
;	\2 -- High bits of fraction.
;	\3 -- Low bits of fraction.
;	\4 -- Exponent.
;	\5 -- High bits of fraction.
;	\6 -- Low bits of fraction.
; 
; RESULT
;	\1 -- Exponent.
;	\2 -- High bits of fraction.
;	\3 -- Low bits of fraction.
;	\4 -- Exponent.
;	\5 -- High bits of fraction.
;	\6 -- Low bits of fraction.
; 
;
ALIGNEXPONENT macro 

	cmp.w			\1,\4
	beq.s			.ExpOk
	bmi.s			.ExpNeg
	
	.ExpPos:
	sub.w			\1,\4
	add.w			\4,\1
	cmp.w			#32,\4
	blt.s			.ExpPosShift
	move.l			#0,\2
	move.l			#0,\3
	bra.s			.ExpOk
	.ExpPosShift:
	LSR64			\4,\2,\3
	bra.s			.ExpOk
	
	.ExpNeg:
	sub.w			\1,\4
	neg.w			\4
	cmp.w			#32,\4
	blt.s			.ExpNegShift
	move.l			#0,\5
	move.l			#0,\6
	bra.s			.ExpOk
	.ExpNegShift:
	LSR64			\4,\5,\6

	.ExpOk:
	move.w			\1,\4
	
endm


;
; Normalizes a double. Pollutes \4!
;
; INPUTS
;	\1 -- Exponent.
;	\2 -- High bits of fraction.
;	\3 -- Low bits of fraction.
;	\4 -- Scratch register.
;
; RESULT
;	\1 -- Exponent.
;	\2 -- High bits of fraction.
;	\3 -- Low bits of fraction.
;
; TODO: detect overflows
; TODO: detect underflows
;
NORMALIZE macro

	; Find leading digit from fraction
	.Normalize:
	bfffo			\2{0:32},\4
	bne.s			.HighNormalize
	bfffo			\3{0:32},\4
	bne.s			.LowNormalize
	
	; If fraction is zero then zero exponent
	move.w			#0,\1
	bra.s			.NormalizeOk
	
	; Normalize starting from high bits
	.HighNormalize:
	cmp.b			#11,\4
	beq.s			.NormalizeOk
	bgt.s			.HighNormalizeLeft
	
	; Shift high bits to right
	.HighNormalizeRight:
	subi.l			#11,\4
	neg.l			\4
	add.w			\4,\1
	LSR64L			\4,\2,\3
	bra.s			.NormalizeOk
	
	; Shift high bits to left
	.HighNormalizeLeft:
	subi.l			#11,\4
	sub.w			\4,\1
	LSL64L			\4,\2,\3
	bra.s			.NormalizeOk
	
	; Normalize starting from low bits
	.LowNormalize:
	move.l			\3,\2
	move.l			#0,\3
	subi.w			#32,\1
	bra.s			.Normalize
	
	; Normalization done
	.NormalizeOk:
	
	; Check for over- and underflows
	; TODO: this is wip
	;tst.l			\1		
	;bgt.s			.NoUnderflow
	;move.w			#0,\1
	;move.l			#0,\2
	;move.l			#0,\3
	;.NoUnderflow:
	;cmp.l			#2047,\1
	;blt.s			.NoOverflow
	;move.w			#$7ff,\1
	;move.l			#0,\2
	;move.l			#0,\3
	;.NoOverflow:
	
endm
