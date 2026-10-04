;
; Callable wrappers around the arithmetic macros (FE_FADD/FE_FMUL/
; FE_FDIV from fadd.asm/fmul.asm/fdiv.asm) for checklist #10's native
; transcendentals. Those macros are inlined at their usual call sites
; (fadd.asm/fsub.asm/fmul.asm/fdiv.asm's own handlers) because that
; code is hot -- reached on every trap -- and CLAUDE.md says to keep
; hot paths flat. A transcendental's range reduction/polynomial
; evaluation is cold code by comparison (reached once per fetox/fsqrt/
; etc. trap, not once per arithmetic step within it) and chains many
; arithmetic steps, so inlining FE_FADD/FE_FMUL/FE_FDIV at every one
; of those steps would multiply each macro's full body (FE_FMUL alone
; is well over 100 instructions) by every step in every transcendental
; -- real code bloat for no benefit. A `jsr`/`rts` wrapper is the
; right tradeoff here specifically because this code is cold, not hot.
;
; All four take dst in d0:d1:d2, src in d3:d4:d5 (the same convention
; FE_FADD/FE_FMUL/FE_FDIV already use) and return the result in
; d0:d1:d2. d6/d7 are left alone (matching the wrapped macros' own
; documented "d7 reserved" convention, and d6 only used as transient
; scratch by them) so callers chaining several of these in a loop can
; keep a counter in d7 across calls.
;
NativeFadd
	FE_FADD
	rts

NativeFsub
	bchg			#31,d3
	FE_FADD
	rts

NativeFmul
	FE_FMUL
	rts

NativeFdiv
	FE_FDIV
	rts


;
; Native square root (checklist #10): Newton-Raphson on the reciprocal
; square root, avoiding fdiv (expensive -- DIV64's 64+1-iteration
; loop) inside the iteration entirely, at the cost of needing a
; division-free initial guess instead.
;
; x = mantissa_value * 2^raw_exp, mantissa_value in [1,2) (the usual
; normalized form, read directly from the operand -- no bit-shifting
; needed). Splitting raw_exp = 2*half + parity (parity 0 or 1, half =
; floor(raw_exp/2) via a plain arithmetic shift, which implements
; floor division correctly for negative raw_exp too): x = m * 2^(2*half)
; where m = mantissa_value * 2^parity, i.e. m is in [1,2) (parity 0)
; or [2,4) (parity 1) -- constructed with NO mantissa bit-shifting at
; all, just by pairing the UNCHANGED mantissa bits with exponent
; 16383+parity instead of the original exponent (doubling a
; normalized mantissa's bit pattern directly doesn't fit back in 64
; bits -- the explicit bit would shift out -- but doubling its VALUE
; is exactly "same bits, exponent one higher", which is all this
; needs). Then sqrt(x) = sqrt(m) * 2^half, and sqrt(m) is computed as
; m*y where y converges to 1/sqrt(m) via y := y*(1.5 - 0.5*m*y^2).
;
; Initial guess: 0.75 if parity 0 (m in [1,2)), 0.5 if parity 1 (m in
; [2,4)) -- both exact, trivial constants (no multiply needed to
; compute them). Verified in Python before writing this: y0=1.0 does
; NOT converge globally (diverges outright for m near 4); these two
; piecewise constants converge to within ~3 ULP of a double-precision
; reference after 6 iterations across 1M+ random samples spanning
; both ranges and their boundaries (m=1, m=2, m=4-epsilon). 7
; iterations (one more than Python needed for double) is used here
; for the wider 64-bit mantissa's extra precision headroom.
;
; INPUTS
;	d0 -- Sign(1):exponent(15):reserved(16). Must be an ordinary
;	      (finite, nonzero, non-NaN/Inf) POSITIVE value -- callers
;	      (fsqrt.asm) are responsible for the 0/1/negative/Inf/NaN
;	      special cases before calling this.
;	d1 -- Mantissa bits 63-32 (explicit integer bit at bit 31).
;	d2 -- Mantissa bits 31-0.
;
; RESULT
;	d0 -- Sign(1):exponent(15):reserved(16) of sqrt(x).
;	d1 -- Mantissa bits 63-32 of sqrt(x).
;	d2 -- Mantissa bits 31-0 of sqrt(x).
;
NativeFsqrt

	; raw_exp = biased exponent - 16383 (signed). half = floor(raw_exp/2)
	; via asr (arithmetic shift -- sign-extending, so this is exactly
	; floor division, including for negative raw_exp). parity =
	; raw_exp - 2*half (always 0 or 1, by construction).
	bfextu			d0{1:15},d6
	sub.l			#16383,d6
	move.l			d6,d4
	asr.l			#1,d4
	move.l			d4,SqrtHalfOffset
	add.l			d4,d4
	sub.l			d4,d6			; d6 = parity (0 or 1)
	move.l			d6,SqrtParity

	; Construct m: mantissa bits (d1:d2) unchanged, exponent 16383+parity.
	add.l			#16383,d6
	lsl.l			#8,d6
	lsl.l			#8,d6
	move.l			d6,SqrtM
	move.l			d1,SqrtM+4
	move.l			d2,SqrtM+8

	; m*0.5, loop-invariant -- computed once rather than once per
	; iteration.
	move.l			SqrtM,d0
	move.l			SqrtM+4,d1
	move.l			SqrtM+8,d2
	lea.l			SqrtConstHalf,a0
	movem.l			(a0),d3/d4/d5
	jsr				NativeFmul
	move.l			d0,SqrtMHalf
	move.l			d1,SqrtMHalf+4
	move.l			d2,SqrtMHalf+8

	; Initial guess, selected by parity (see header comment).
	tst.l			SqrtParity
	bne.s			.ParityOne
	lea.l			SqrtConstThreeQuarter,a0
	bra.s			.GotY0
	.ParityOne:
	lea.l			SqrtConstHalf,a0
	.GotY0:
	movem.l			(a0),d0/d1/d2
	move.l			d0,SqrtY
	move.l			d1,SqrtY+4
	move.l			d2,SqrtY+8

	; Newton-Raphson: y := y*(1.5 - 0.5*m*y^2), 7 times. d7 (the loop
	; counter) survives every NativeFmul/NativeFsub call below -- both
	; wrap macros that document d7 as reserved/untouched.
	moveq			#7,d7
	.Iterate:

	; t1 = y*y
	move.l			SqrtY,d0
	move.l			SqrtY+4,d1
	move.l			SqrtY+8,d2
	move.l			d0,d3
	move.l			d1,d4
	move.l			d2,d5
	jsr				NativeFmul
	move.l			d0,SqrtT1
	move.l			d1,SqrtT1+4
	move.l			d2,SqrtT1+8

	; t2 = (m*0.5) * t1
	move.l			SqrtMHalf,d0
	move.l			SqrtMHalf+4,d1
	move.l			SqrtMHalf+8,d2
	move.l			SqrtT1,d3
	move.l			SqrtT1+4,d4
	move.l			SqrtT1+8,d5
	jsr				NativeFmul
	move.l			d0,SqrtT1
	move.l			d1,SqrtT1+4
	move.l			d2,SqrtT1+8

	; t3 = 1.5 - t2
	lea.l			SqrtConstOnePtFive,a0
	movem.l			(a0),d0/d1/d2
	move.l			SqrtT1,d3
	move.l			SqrtT1+4,d4
	move.l			SqrtT1+8,d5
	jsr				NativeFsub
	move.l			d0,SqrtT1
	move.l			d1,SqrtT1+4
	move.l			d2,SqrtT1+8

	; y = y * t3
	move.l			SqrtY,d0
	move.l			SqrtY+4,d1
	move.l			SqrtY+8,d2
	move.l			SqrtT1,d3
	move.l			SqrtT1+4,d4
	move.l			SqrtT1+8,d5
	jsr				NativeFmul
	move.l			d0,SqrtY
	move.l			d1,SqrtY+4
	move.l			d2,SqrtY+8

	subq.l			#1,d7
	bne.w			.Iterate

	; sqrt(m) = m*y (normalized to [1,2) automatically by NativeFmul,
	; since sqrt of m in [1,4) is mathematically in [1,2)); then scale
	; by 2^half via a plain exponent bump -- the same technique #5/#9
	; already use, no further multiply needed.
	move.l			SqrtM,d0
	move.l			SqrtM+4,d1
	move.l			SqrtM+8,d2
	move.l			SqrtY,d3
	move.l			SqrtY+4,d4
	move.l			SqrtY+8,d5
	jsr				NativeFmul
	bfextu			d0{1:15},d6
	add.l			SqrtHalfOffset,d6
	lsl.l			#8,d6
	lsl.l			#8,d6
	move.l			d6,d0
	rts

SqrtConstHalf			dc.l	$3ffe0000,$80000000,$00000000	; 0.5
SqrtConstOnePtFive		dc.l	$3fff0000,$c0000000,$00000000	; 1.5
SqrtConstThreeQuarter	dc.l	$3ffe0000,$c0000000,$00000000	; 0.75
SqrtHalfOffset			dc.l	0
SqrtParity				dc.l	0
SqrtM					dc.l	0,0,0
SqrtMHalf				dc.l	0,0,0
SqrtY					dc.l	0,0,0
SqrtT1					dc.l	0,0,0
