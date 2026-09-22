;
; FPU registers.
;
; Native 68881/68882 extended layout, 12 bytes/register (checklist #4):
; word0 = sign(1):exponent(15, bias 16383), word1 = reserved (always 0),
; word2/word3 = 64-bit mantissa with an EXPLICIT integer bit at bit 63
; (no hidden-bit convention, unlike the IEEE double this replaced) --
; see DESIGN-04-native-extended-repr.md. As a register triple (d0/d1/d2)
; this is: d0 = sign+exponent+reserved, d1 = mantissa hi32, d2 = mantissa
; lo32. fmove.x/fmovem.x's real 68881 memory format is byte-identical to
; this, so that direction is now a straight movem.l with zero conversion.
	ifnd FPN080
RegFpn				dc.l	0,0,0, 0,0,0, 0,0,0, 0,0,0
					dc.l	0,0,0, 0,0,0, 0,0,0, 0,0,0
					dc.l	0,0,0, 0,0,0, 0,0,0, 0,0,0
					dc.l	0,0,0, 0,0,0, 0,0,0, 0,0,0
	endif
RegFpcrReserved		dc.w	0
RegFpcrEnable		dc.b	0
RegFpcrMode			dc.b	0
	ifnd FPSR080
RegFpsrCc			dc.b	0
RegFpsrQuotient		dc.b	0
RegFpsrExc			dc.b	0
RegFpsrAexc			dc.b	0
	endif
RegFpiar			dc.l	0


;
; FPU constants.
;
CCNAN				equ		$01
CCI					equ		$02
CCZ					equ		$04
CCN					equ		$08


;
; flags in the FPCR mode byte
;
FPCR_ROUNDMASK		EQU	$30
FPCR_NATURAL		EQU	$00	;after masking: $00 - round to nearest (0.5 = up)
FPCR_RZ				EQU	$10	;after masking: $10 - round to zero
FPCR_FLOOR			EQU	$20	;after masking: $20 - round to -infinity
FPCR_CEIL			EQU	$30	;after masking: $30 - round to +infinity

; rounding PRECISION field (bits 7-6, distinct from the rounding MODE
; field above) -- checklist #5's single-precision fast path trigger
FPCR_PRECMASK		EQU	$C0
FPCR_EXTENDED		EQU	$00	;after masking: $00 - extended (80-bit) precision
FPCR_SINGLE			EQU	$40	;after masking: $40 - round every result to single
FPCR_DOUBLE			EQU	$80	;after masking: $80 - round every result to double


;
; FPSR condition code truth table.
;
FPSRCCTRUTH				
	dc.l			$cccccccc,$ff00ff00,$cccccccc,$ff00ff00
	dc.l			$aaaaaaaa,$bf2abf2a,$aaaaaaaa,$bf2abf2a
	dc.l			$f0f0f0f0,$ff00ff00,$f0f0f0f0,$ff00ff00
	dc.l			$aaaaaaaa,$bf2abf2a,$aaaaaaaa,$bf2abf2a


;
; FPU constant ROM.
;
CCC
	dc.l			$400921fb,$54442d18
	dc.l			$00000000,$00000000
	dc.l			$00000000,$00000000
	dc.l			$00000000,$00000000
	dc.l			$00000000,$00000000
	dc.l			$00000000,$00000000
	dc.l			$00000000,$00000000
	dc.l			$00000000,$00000000
	dc.l			$00000000,$00000000
	dc.l			$00000000,$00000000
	dc.l			$00000000,$00000000
	dc.l			$3fd34413,$509f79fe
	dc.l			$4005bf0a,$8b145769
	dc.l			$3ff71547,$652b82fe
	dc.l			$3fdbcb7b,$1526e50e
	dc.l			$00000000,$00000000
	dc.l			$00000000,$00000000
	dc.l			$00000000,$00000000
	dc.l			$00000000,$00000000
	dc.l			$00000000,$00000000
	dc.l			$00000000,$00000000
	dc.l			$00000000,$00000000
	dc.l			$00000000,$00000000
	dc.l			$00000000,$00000000
	dc.l			$00000000,$00000000
	dc.l			$00000000,$00000000
	dc.l			$00000000,$00000000
	dc.l			$00000000,$00000000
	dc.l			$00000000,$00000000
	dc.l			$00000000,$00000000
	dc.l			$00000000,$00000000
	dc.l			$00000000,$00000000
	dc.l			$00000000,$00000000
	dc.l			$00000000,$00000000
	dc.l			$00000000,$00000000
	dc.l			$00000000,$00000000
	dc.l			$00000000,$00000000
	dc.l			$00000000,$00000000
	dc.l			$00000000,$00000000
	dc.l			$00000000,$00000000
	dc.l			$00000000,$00000000
	dc.l			$00000000,$00000000
	dc.l			$00000000,$00000000
	dc.l			$00000000,$00000000
	dc.l			$00000000,$00000000
	dc.l			$00000000,$00000000
	dc.l			$00000000,$00000000
	dc.l			$00000000,$00000000
	dc.l			$3fe62e42,$fefa39ef
	dc.l			$40026bb1,$bbb55515
	dc.l			$3ff00000,$00000000
	dc.l			$40240000,$00000000
	dc.l			$40590000,$00000000
	dc.l			$40c38800,$00000000
	dc.l			$4197d784,$00000000
	dc.l			$4341c379,$37e08000
	dc.l			$4693b8b5,$b5056e16
	dc.l			$4d384f03,$e93ff9f4
	dc.l			$5a827748,$f9301d31
	dc.l			$75154fdd,$7f73bf3b
	dc.l			$7ff00000,$00000000
	dc.l			$7ff00000,$00000000
	dc.l			$7ff00000,$00000000
	dc.l			$7ff00000,$00000000
	dc.l			$00000000,$00000000
	dc.l			$00000000,$00000000
	dc.l			$00000000,$00000000
	dc.l			$00000000,$00000000
	dc.l			$00000000,$00000000
	dc.l			$00000000,$00000000
	dc.l			$00000000,$00000000
	dc.l			$00000000,$00000000
	dc.l			$00000000,$00000000
	dc.l			$00000000,$00000000
	dc.l			$00000000,$00000000
	dc.l			$00000000,$00000000
	dc.l			$00000000,$00000000
	dc.l			$00000000,$00000000
	dc.l			$00000000,$00000000
	dc.l			$00000000,$00000000
	dc.l			$00000000,$00000000
	dc.l			$00000000,$00000000
	dc.l			$00000000,$00000000
	dc.l			$00000000,$00000000
	dc.l			$00000000,$00000000
	dc.l			$00000000,$00000000
	dc.l			$00000000,$00000000
	dc.l			$00000000,$00000000
	dc.l			$00000000,$00000000
	dc.l			$00000000,$00000000
	dc.l			$00000000,$00000000
	dc.l			$00000000,$00000000
	dc.l			$00000000,$00000000
	dc.l			$00000000,$00000000
	dc.l			$00000000,$00000000
	dc.l			$00000000,$00000000
	dc.l			$00000000,$00000000
	dc.l			$00000000,$00000000
	dc.l			$00000000,$00000000
	dc.l			$00000000,$00000000
	dc.l			$00000000,$00000000
	dc.l			$00000000,$00000000
	dc.l			$00000000,$00000000
	dc.l			$00000000,$00000000
	dc.l			$00000000,$00000000
	dc.l			$00000000,$00000000
	dc.l			$00000000,$00000000
	dc.l			$00000000,$00000000
	dc.l			$00000000,$00000000
	dc.l			$00000000,$00000000
	dc.l			$00000000,$00000000
	dc.l			$00000000,$00000000
	dc.l			$00000000,$00000000
	dc.l			$00000000,$00000000
	dc.l			$00000000,$00000000
	dc.l			$00000000,$00000000
	dc.l			$00000000,$00000000
	dc.l			$00000000,$00000000
	dc.l			$00000000,$00000000
	dc.l			$00000000,$00000000
	dc.l			$00000000,$00000000
	dc.l			$00000000,$00000000
	dc.l			$00000000,$00000000
	dc.l			$00000000,$00000000
	dc.l			$00000000,$00000000
	dc.l			$00000000,$00000000
	dc.l			$00000000,$00000000
	dc.l			$00000000,$00000000
