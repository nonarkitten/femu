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
; d0:d1:d2. d6 is left alone too (only used as transient scratch by the
; wrapped macros). d7 is NOT available to callers despite the wrapped
; macros' own "d7 reserved" convention -- that convention means the
; macros themselves don't touch it, not that nothing else cares what's
; in it. d7 is INSTRUCTION (src/utils/constants.asm: `INSTRUCTION equr
; d7`), the live decoded opcode word every handler's GETREGISTER (and
; HandleException's own chain-loop decode) reads AFTER the handler
; returns -- clobbering it here corrupts the destination FPn index the
; caller's GETREGISTER extracts next, silently writing the correct
; result into the WRONG register. Found the hard way: a Horner-loop
; counter in d7 made fetox write its answer into whatever FPn the
; mangled opcode word decoded to, while fp0 (the real destination for
; the "fp0,fp0" test vectors) kept its original, unmodified input --
; "wrong answer" looked exactly like "the op didn't run" for a monadic,
; self-overwriting op. A loop counter that needs to survive a chained
; NativeFmul/NativeFadd/NativeFsub call therefore belongs in memory
; (see ExpIterCount below), never in d7.
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

	; Newton-Raphson: y := y*(1.5 - 0.5*m*y^2), 7 times. The loop counter
	; lives in memory, not a register -- see this file's header comment
	; on why d7 specifically must never hold it (d7 is INSTRUCTION, and
	; NativeFmul/NativeFsub below don't touch it, but something further
	; up the call chain, after this routine returns, does).
	move.l			#7,SqrtIterCount
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

	subq.l			#1,SqrtIterCount
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
SqrtIterCount			dc.l	0
SqrtM					dc.l	0,0,0
SqrtMHalf				dc.l	0,0,0
SqrtY					dc.l	0,0,0
SqrtT1					dc.l	0,0,0


;
; Rounds an extended value to the nearest integer (ties to even),
; returned as a plain signed 32-bit integer -- NOT another extended
; float. Used by checklist #10's range-reduction steps (e.g. NativeFexp
; below) to get an integer exponent count cheaply, without going
; through a float-typed round-to-integer and back.
;
; Correct (verified against an exact-Fraction reference in Python,
; 0/500000 random cases across biased exponents 16378-16413) for any
; operand whose rounded magnitude fits in 31 bits -- i.e. raw exponent
; (biased - 16383) in roughly [-1,30]. Every caller in this file only
; ever rounds a range-reduction quotient (bounded well inside that by
; construction: a quotient needing a 31-bit integer part would already
; put the final result past over/underflow), so this isn't hardened
; beyond that range.
;
; INPUTS
;	d0 -- Sign(1):exponent(15):reserved(16).
;	d1 -- Mantissa bits 63-32 (explicit integer bit at bit 31).
;	d2 -- Mantissa bits 31-0.
;
; RESULT
;	d0 -- The rounded value, as a signed 32-bit integer.
;
NativeRoundToInt
	move.l			d0,d6
	and.l			#$80000000,d6		; d6 = sign only
	bfextu			d0{1:15},d0
	sub.l			#16383,d0			; d0 = raw_exp (signed)
	bmi.s			.LessThanOne
	moveq			#31,d3
	sub.l			d0,d3				; d3 = frac_bits_in_d1 (1..31)
	moveq			#1,d4
	lsl.l			d3,d4
	subq.l			#1,d4				; d4 = mask
	move.l			d1,d5
	and.l			d4,d5				; d5 = d1's fractional bits
	move.l			d1,d0
	lsr.l			d3,d0				; d0 = integer magnitude
	subq.l			#1,d3				; d3 = round-bit position
	btst			d3,d5
	beq.s			.NoRoundUp
	bclr			d3,d5				; d5 = sticky bits below the round bit
	tst.l			d5
	bne.s			.RoundUp
	tst.l			d2
	bne.s			.RoundUp
	btst			#0,d0
	beq.s			.NoRoundUp
	.RoundUp:
	addq.l			#1,d0
	.NoRoundUp:
	bra.s			.ApplySign
	.LessThanOne:
	cmp.l			#-1,d0
	bne.s			.Zero
	cmp.l			#$80000000,d1
	bls.s			.Zero
	moveq			#1,d0
	bra.s			.ApplySign
	.Zero:
	moveq			#0,d0
	.ApplySign:
	tst.l			d6
	beq.s			.Done
	neg.l			d0
	.Done:
	rts


;
; Converts a plain signed 32-bit integer to an extended value. The
; inverse of NativeRoundToInt, used to turn an integer exponent count
; back into a float so it can be multiplied against a constant like
; ln(2) (see NativeFexp below).
;
; INPUTS
;	d0 -- A signed 32-bit integer.
;
; RESULT
;	d0 -- Sign(1):exponent(15):reserved(16).
;	d1 -- Mantissa bits 63-32 (explicit integer bit at bit 31).
;	d2 -- Mantissa bits 31-0.
;
NativeIntToExtended
	tst.l			d0
	bne.s			.NonZero
	moveq			#0,d0
	moveq			#0,d1
	moveq			#0,d2
	rts
	.NonZero:
	; Sign test must run BEFORE anything touches d6 -- bpl/bmi read the
	; flags the entry tst.l d0 left behind (bne above doesn't disturb
	; them), but a "moveq #0,d6" sitting in between would set its OWN
	; N/Z flags (always N=0) and make bpl always take the "positive"
	; branch regardless of d0's real sign. Caught via a bench vector
	; (fetox of a negative x) that silently round-tripped a negative k
	; into a huge positive extended value instead of either negating or
	; erroring.
	bmi.s			.Negative
	moveq			#0,d6
	bra.s			.GotSign
	.Negative:
	moveq			#1,d6
	neg.l			d0
	.GotSign:
	bfffo			d0{0:32},d3			; d3 = bit position of the first 1,
										; counting from bit31 (0 if bit31 set)
	move.l			d0,d1
	lsl.l			d3,d1				; left-justify: top set bit now at bit31
	moveq			#0,d2
	moveq			#31,d0
	sub.l			d3,d0				; d0 = e (0-indexed bit position of the
										; original top set bit, from bit0)
	add.l			#16383,d0
	lsl.l			#8,d0
	lsl.l			#8,d0
	neg.l			d6
	and.l			#$80000000,d6
	or.l			d6,d0
	rts


;
; Native e^x (checklist #10): standard range reduction (x = k*ln(2) + r,
; k integer, |r| <= ln(2)/2) then a Horner-evaluated Taylor polynomial
; for e^r, then 2^k applied as a plain exponent bump (exact, same
; technique #5/#9 already use -- no extra multiply needed).
;
; k = round(x * (1/ln2)) via NativeRoundToInt; r = x - k*ln(2), computed
; with the SAME extended-precision ln(2) constant used for k's own
; derivation (ExpLn2/ExpInvLn2 below), not a re-derived approximation,
; so the two don't disagree with each other.
;
; 16 terms (1/0! through 1/15!) were verified in Python (exact Decimal
; arithmetic, not host-double-limited) to bring the Taylor series'
; OWN truncation error below 2^-63 (this format's mantissa precision)
; across the whole reduced range |r| <= ln(2)/2 well before writing
; any assembly -- truncation stops being the dominant error source at
; that point; what's left is ordinary accumulated rounding from the 16
; multiply-add steps themselves, same as any other chained computation
; in this codebase.
;
; INPUTS
;	d0 -- Sign(1):exponent(15):reserved(16). Must be an ordinary
;	      (finite, non-NaN/Inf) value -- callers (fetox.asm) are
;	      responsible for the 0/Inf/NaN special cases before calling
;	      this. Not hardened against |x| large enough that k itself
;	      would need more than ~30 bits (see NativeRoundToInt) --
;	      covers every x that wouldn't already overflow/underflow
;	      e^x's own 15-bit result exponent field by a wide margin.
;	d1 -- Mantissa bits 63-32 (explicit integer bit at bit 31).
;	d2 -- Mantissa bits 31-0.
;
; RESULT
;	d0 -- Sign(1):exponent(15):reserved(16) of e^x.
;	d1 -- Mantissa bits 63-32 of e^x.
;	d2 -- Mantissa bits 31-0 of e^x.
;
NativeFexp
	move.l			d0,ExpX
	move.l			d1,ExpX+4
	move.l			d2,ExpX+8

	; k = round(x * 1/ln2)
	move.l			d0,d3
	move.l			d1,d4
	move.l			d2,d5
	lea.l			ExpInvLn2,a0
	movem.l			(a0),d0/d1/d2
	jsr				NativeFmul
	jsr				NativeRoundToInt
	move.l			d0,ExpK

	; k_ln2 = (k as a float) * ln(2)
	jsr				NativeIntToExtended
	move.l			d0,d3
	move.l			d1,d4
	move.l			d2,d5
	lea.l			ExpLn2,a0
	movem.l			(a0),d0/d1/d2
	jsr				NativeFmul

	; r = x - k_ln2
	move.l			d0,d3
	move.l			d1,d4
	move.l			d2,d5
	move.l			ExpX,d0
	move.l			ExpX+4,d1
	move.l			ExpX+8,d2
	jsr				NativeFsub
	move.l			d0,ExpR
	move.l			d1,ExpR+4
	move.l			d2,ExpR+8

	; Horner evaluation: result = C15; for n=14 downto 0,
	; result := result*r + Cn. a0 walks the constant table forward
	; from ExpC14 (ExpC15 seeds the accumulator first, outside the
	; loop) -- the constants are declared contiguously, 12 bytes
	; apart, highest-term-first in the source but therefore lowest-
	; address-first in memory, purely so this can be a plain address
	; increment instead of an indexed lookup.
	lea.l			ExpC15,a0
	movem.l			(a0),d0/d1/d2
	move.l			d0,ExpResult
	move.l			d1,ExpResult+4
	move.l			d2,ExpResult+8
	lea.l			ExpC14,a0
	move.l			#14,ExpIterCount
	.HornerLoop:
	move.l			ExpResult,d0
	move.l			ExpResult+4,d1
	move.l			ExpResult+8,d2
	move.l			ExpR,d3
	move.l			ExpR+4,d4
	move.l			ExpR+8,d5
	jsr				NativeFmul
	move.l			d0,ExpResult
	move.l			d1,ExpResult+4
	move.l			d2,ExpResult+8
	move.l			ExpResult,d0
	move.l			ExpResult+4,d1
	move.l			ExpResult+8,d2
	movem.l			(a0),d3/d4/d5
	jsr				NativeFadd
	move.l			d0,ExpResult
	move.l			d1,ExpResult+4
	move.l			d2,ExpResult+8
	adda.l			#12,a0
	subq.l			#1,ExpIterCount
	bpl.w			.HornerLoop

	; e^x = e^r * 2^k -- exponent bump, not a multiply. Clamps to
	; Infinity/zero if k pushes the exponent field out of range
	; (rare -- only for |x| large enough that e^x over/underflows
	; anyway), rather than silently wrapping to a wrong finite value.
	move.l			ExpResult,d0
	move.l			ExpResult+4,d1
	move.l			ExpResult+8,d2
	bfextu			d0{1:15},d6
	add.l			ExpK,d6
	cmp.l			#1,d6
	blt.s			.Underflow
	cmp.l			#32766,d6
	bgt.s			.Overflow
	lsl.l			#8,d6
	lsl.l			#8,d6
	move.l			d6,d0
	rts
	.Overflow:
	move.l			#$7fff0000,d0
	move.l			#$80000000,d1
	moveq			#0,d2
	rts
	.Underflow:
	moveq			#0,d0
	moveq			#0,d1
	moveq			#0,d2
	rts

ExpInvLn2	dc.l	$3fff0000,$b8aa3b29,$5c17f0bc	; 1/ln(2)
ExpLn2		dc.l	$3ffe0000,$b17217f7,$d1cf79ac	; ln(2)
; ln(10)/1-over-ln(10): shared by ftentox's general case (10^x =
; e^(x*ln(10))) and flog10's (log10(x) = ln(x)/ln(10)) -- checklist
; #10, not just #9's integer-exponent ftwotox fast path.
ExpLn10		dc.l	$40000000,$935d8ddd,$aaa8ac17	; ln(10)
ExpInvLn10	dc.l	$3ffd0000,$de5bd8a9,$37287195	; 1/ln(10)
ExpX		dc.l	0,0,0
ExpK		dc.l	0
ExpR		dc.l	0,0,0
ExpResult	dc.l	0,0,0
ExpIterCount	dc.l	0
ExpC15		dc.l	$3fd60000,$d73f9f39,$9dc0f88f	; 1/15!
ExpC14		dc.l	$3fda0000,$c9cba546,$03e4e906	; 1/14!
ExpC13		dc.l	$3fde0000,$b092309d,$43684be5	; 1/13!
ExpC12		dc.l	$3fe20000,$8f76c77f,$c6c4bdaa	; 1/12!
ExpC11		dc.l	$3fe50000,$d7322b3f,$aa271c7f	; 1/11!
ExpC10		dc.l	$3fe90000,$93f27dbb,$c4fae397	; 1/10!
ExpC9		dc.l	$3fec0000,$b8ef1d2a,$b6399c7d	; 1/9!
ExpC8		dc.l	$3fef0000,$d00d00d0,$0d00d00d	; 1/8!
ExpC7		dc.l	$3ff20000,$d00d00d0,$0d00d00d	; 1/7!
ExpC6		dc.l	$3ff50000,$b60b60b6,$0b60b60b	; 1/6!
ExpC5		dc.l	$3ff80000,$88888888,$88888889	; 1/5!
ExpC4		dc.l	$3ffa0000,$aaaaaaaa,$aaaaaaab	; 1/4!
ExpC3		dc.l	$3ffc0000,$aaaaaaaa,$aaaaaaab	; 1/3!
ExpC2		dc.l	$3ffe0000,$80000000,$00000000	; 1/2!
ExpC1		dc.l	$3fff0000,$80000000,$00000000	; 1/1!
ExpC0		dc.l	$3fff0000,$80000000,$00000000	; 1/0!


;
; Native ln(x) (checklist #10): x = m * 2^e, m in [1,2) -- read
; directly from the operand's own exponent/mantissa split, no bit-
; shifting needed (the same free normalization #10's other routines
; already rely on). ln(x) = ln(m) + e*ln(2), with e*ln(2) reusing
; NativeFexp's own ExpLn2 constant above rather than a second copy.
;
; ln(m) uses the atanh series: s = (m-1)/(m+1), ln(m) = 2*atanh(s) =
; 2*s*(1 + s^2/3 + s^4/5 + s^6/7 + ...). m in [1,2) alone gives s up to
; 1/3, needing an impractically long series (verified in Python: ~20
; terms for 2^-63) -- so m is first centered against sqrt(2): if
; m >= sqrt(2), m := m/sqrt(2) and ln(2)/2 is added back once ln(m/
; sqrt(2)) is known (ln(m) = ln(m/sqrt(2)) + ln(sqrt(2))); otherwise m
; is already in [1,sqrt(2)) and the correction is 0. This halves s's
; range to at most (sqrt(2)-1)/(sqrt(2)+1) ~= 0.1716, and since m and
; sqrt(2) share the same exponent (16383) by construction, "m >=
; sqrt(2)" is just an unsigned 64-bit mantissa compare -- no general
; float comparison needed.
;
; 13 terms (1/1, 1/3, ..., 1/25) were verified in Python (exact Decimal
; arithmetic, 300000+ random samples plus the m=1/m->sqrt(2) boundary
; cases) to bring the series' OWN truncation error to ~0.0015 ULP
; (this format's mantissa precision) across the whole reduced range,
; well before writing any assembly -- same margin #10's other rows use.
;
; INPUTS
;	d0 -- Sign(1):exponent(15):reserved(16). Must be an ordinary
;	      (finite, positive, nonzero, non-NaN/Inf) value -- callers
;	      (flogn.asm) are responsible for the 0/negative/Inf/NaN
;	      special cases before calling this.
;	d1 -- Mantissa bits 63-32 (explicit integer bit at bit 31).
;	d2 -- Mantissa bits 31-0.
;
; RESULT
;	d0 -- Sign(1):exponent(15):reserved(16) of ln(x).
;	d1 -- Mantissa bits 63-32 of ln(x).
;	d2 -- Mantissa bits 31-0 of ln(x).
;
NativeFlogn
	; e = biased exponent - 16383 (signed); m = operand with its
	; exponent field replaced by 16383 (mantissa bits d1:d2 untouched
	; -- the operand is already normalized, so this literally IS m).
	bfextu			d0{1:15},d6
	sub.l			#16383,d6
	move.l			d6,LognE
	move.l			#$3fff0000,d0

	; Correction defaults to 0; becomes ln(2)/2 below if m needs
	; centering against sqrt(2).
	moveq			#0,d6
	move.l			d6,LognCorrection
	move.l			d6,LognCorrection+4
	move.l			d6,LognCorrection+8

	cmp.l			LognConstSqrt2+4,d1
	bhi.s			.NeedsCenter
	blo.s			.NoCenter
	cmp.l			LognConstSqrt2+8,d2
	blo.s			.NoCenter
	.NeedsCenter:
	move.l			d0,d3
	move.l			d1,d4
	move.l			d2,d5
	lea.l			LognConstInvSqrt2,a0
	movem.l			(a0),d0/d1/d2
	jsr				NativeFmul
	lea.l			LognConstHalfLn2,a0
	movem.l			(a0),d3/d4/d5
	move.l			d3,LognCorrection
	move.l			d4,LognCorrection+4
	move.l			d5,LognCorrection+8
	.NoCenter:

	; s = (m-1)/(m+1)
	move.l			d0,LognM
	move.l			d1,LognM+4
	move.l			d2,LognM+8
	lea.l			LognConstOne,a0
	movem.l			(a0),d3/d4/d5
	jsr				NativeFsub
	move.l			d0,LognNum
	move.l			d1,LognNum+4
	move.l			d2,LognNum+8
	move.l			LognM,d0
	move.l			LognM+4,d1
	move.l			LognM+8,d2
	lea.l			LognConstOne,a0
	movem.l			(a0),d3/d4/d5
	jsr				NativeFadd
	move.l			d0,d3
	move.l			d1,d4
	move.l			d2,d5
	move.l			LognNum,d0
	move.l			LognNum+4,d1
	move.l			LognNum+8,d2
	jsr				NativeFdiv
	move.l			d0,LognS
	move.l			d1,LognS+4
	move.l			d2,LognS+8

	; s2 = s*s
	move.l			d0,d3
	move.l			d1,d4
	move.l			d2,d5
	jsr				NativeFmul
	move.l			d0,LognS2
	move.l			d1,LognS2+4
	move.l			d2,LognS2+8

	; Horner evaluation: result = C12; for n=11 downto 0,
	; result := result*s2 + Cn. Same address-increment trick as
	; NativeFexp's Horner loop (see there for why the constants are
	; declared highest-term-first in source, lowest-address-first in
	; memory).
	lea.l			LognC12,a0
	movem.l			(a0),d0/d1/d2
	move.l			d0,LognResult
	move.l			d1,LognResult+4
	move.l			d2,LognResult+8
	lea.l			LognC11,a0
	move.l			#11,LognIterCount
	.HornerLoop:
	move.l			LognResult,d0
	move.l			LognResult+4,d1
	move.l			LognResult+8,d2
	move.l			LognS2,d3
	move.l			LognS2+4,d4
	move.l			LognS2+8,d5
	jsr				NativeFmul
	move.l			d0,LognResult
	move.l			d1,LognResult+4
	move.l			d2,LognResult+8
	move.l			LognResult,d0
	move.l			LognResult+4,d1
	move.l			LognResult+8,d2
	movem.l			(a0),d3/d4/d5
	jsr				NativeFadd
	move.l			d0,LognResult
	move.l			d1,LognResult+4
	move.l			d2,LognResult+8
	adda.l			#12,a0
	subq.l			#1,LognIterCount
	bpl.w			.HornerLoop

	; ln(m) = 2*s*poly -- the *2 is a plain exponent bump (same
	; technique used throughout #10), not a multiply. Always positive
	; (s>=0, poly>0), so discarding the sign bit here is safe, same as
	; NativeFsqrt/NativeFexp's own final bumps.
	move.l			LognS,d0
	move.l			LognS+4,d1
	move.l			LognS+8,d2
	move.l			LognResult,d3
	move.l			LognResult+4,d4
	move.l			LognResult+8,d5
	jsr				NativeFmul
	bfextu			d0{1:15},d6
	addq.l			#1,d6
	lsl.l			#8,d6
	lsl.l			#8,d6
	move.l			d6,d0

	; + correction (0 or ln(2)/2, from the sqrt(2)-centering step)
	move.l			d0,d3
	move.l			d1,d4
	move.l			d2,d5
	move.l			LognCorrection,d0
	move.l			LognCorrection+4,d1
	move.l			LognCorrection+8,d2
	jsr				NativeFadd
	move.l			d0,LognLnM
	move.l			d1,LognLnM+4
	move.l			d2,LognLnM+8

	; + e*ln(2)
	move.l			LognE,d0
	jsr				NativeIntToExtended
	move.l			d0,d3
	move.l			d1,d4
	move.l			d2,d5
	lea.l			ExpLn2,a0
	movem.l			(a0),d0/d1/d2
	jsr				NativeFmul
	move.l			d0,d3
	move.l			d1,d4
	move.l			d2,d5
	move.l			LognLnM,d0
	move.l			LognLnM+4,d1
	move.l			LognLnM+8,d2
	jsr				NativeFadd
	rts

LognConstSqrt2		dc.l	$3fff0000,$b504f333,$f9de6484	; sqrt(2)
LognConstInvSqrt2	dc.l	$3ffe0000,$b504f333,$f9de6484	; 1/sqrt(2)
LognConstHalfLn2	dc.l	$3ffd0000,$b17217f7,$d1cf79ac	; ln(2)/2
LognConstOne		dc.l	$3fff0000,$80000000,$00000000	; 1.0
LognE				dc.l	0
LognCorrection		dc.l	0,0,0
LognM				dc.l	0,0,0
LognNum				dc.l	0,0,0
LognS				dc.l	0,0,0
LognS2				dc.l	0,0,0
LognResult			dc.l	0,0,0
LognIterCount		dc.l	0
LognLnM				dc.l	0,0,0
LognC12		dc.l	$3ffa0000,$a3d70a3d,$70a3d70a	; 1/25
LognC11		dc.l	$3ffa0000,$b21642c8,$590b2164	; 1/23
LognC10		dc.l	$3ffa0000,$c30c30c3,$0c30c30c	; 1/21
LognC9		dc.l	$3ffa0000,$d79435e5,$0d79435e	; 1/19
LognC8		dc.l	$3ffa0000,$f0f0f0f0,$f0f0f0f1	; 1/17
LognC7		dc.l	$3ffb0000,$88888888,$88888889	; 1/15
LognC6		dc.l	$3ffb0000,$9d89d89d,$89d89d8a	; 1/13
LognC5		dc.l	$3ffb0000,$ba2e8ba2,$e8ba2e8c	; 1/11
LognC4		dc.l	$3ffb0000,$e38e38e3,$8e38e38e	; 1/9
LognC3		dc.l	$3ffc0000,$92492492,$49249249	; 1/7
LognC2		dc.l	$3ffc0000,$cccccccc,$cccccccd	; 1/5
LognC1		dc.l	$3ffd0000,$aaaaaaaa,$aaaaaaab	; 1/3
LognC0		dc.l	$3fff0000,$80000000,$00000000	; 1/1


;
; Native sin(x) and cos(x), computed together (checklist #10):
; standard quadrant range reduction (x = n*(pi/2) + r, n = round(x *
; 2/pi), |r| <= pi/4) then separate Horner-evaluated Maclaurin
; polynomials for sin(r)/cos(r), then the usual sin/cos-of-sum
; quadrant table to turn (sin(r),cos(r)) back into (sin(x),cos(x)).
; One routine instead of two, since fsin.asm/fcos.asm/the future
; fsincos.asm all need the exact same reduction and only the final
; quadrant-table result differs -- a second (and third) caller showing
; up immediately is what justifies sharing this, not speculation.
;
; n mod 4 selects the quadrant via the standard identities:
;   n&3=0: sin(x)= sin(r), cos(x)= cos(r)
;   n&3=1: sin(x)= cos(r), cos(x)=-sin(r)
;   n&3=2: sin(x)=-sin(r), cos(x)=-cos(r)
;   n&3=3: sin(x)=-cos(r), cos(x)= sin(r)
; "n&3" (not a general mod) relies on n being two's-complement and 4
; being a power of two -- it gives the correct 0..3 result even for
; negative n (e.g. n=-1, all-ones, &3 = 3 = the correct floor-mod),
; the same trick NativeFsqrt's parity split uses for its own exponent.
;
; 11 terms per series (verified in Python, exact Decimal arithmetic
; against an independently-derived high-precision pi, 50000+ random
; |r|<=pi/4 samples plus the r=0/r=+-pi/4 boundary cases) bring each
; series' OWN truncation error to a small fraction of a ULP, the same
; margin #10's other rows use. The range reduction itself uses a
; single 64-bit-mantissa pi/2 constant (SinCosHalfPi below), not a
; multi-word one -- verified in Python to stay accurate to within
; double precision for |x| up to a few thousand (the catastrophic-
; cancellation error in x-n*(pi/2) grows with |x|, same as any "plain"
; sin/cos implementation without Payne-Hanek-style huge-argument
; reduction); nothing in this codebase's own test range comes close to
; that, and chasing arbitrary-magnitude accuracy is explicitly out of
; scope for a row whose point is portability, not precision records.
;
; INPUTS
;	d0 -- Sign(1):exponent(15):reserved(16). Must be an ordinary
;	      (finite, non-NaN/Inf) value -- callers (fsin.asm/fcos.asm)
;	      are responsible for the Inf/NaN special cases before calling
;	      this (unlike fetox/fsqrt/flogn, sin/cos have no zero special
;	      case to intercept either -- r=0 falls out of the Horner loop
;	      correctly on its own, see flogn's own s=0 case for why).
;	d1 -- Mantissa bits 63-32 (explicit integer bit at bit 31).
;	d2 -- Mantissa bits 31-0.
;
; RESULT
;	d0 -- Sign(1):exponent(15):reserved(16) of sin(x).
;	d1 -- Mantissa bits 63-32 of sin(x).
;	d2 -- Mantissa bits 31-0 of sin(x).
;	d3 -- Sign(1):exponent(15):reserved(16) of cos(x).
;	d4 -- Mantissa bits 63-32 of cos(x).
;	d5 -- Mantissa bits 31-0 of cos(x).
;
NativeFsincos
	move.l			d0,SincosX
	move.l			d1,SincosX+4
	move.l			d2,SincosX+8

	; n = round(x * 2/pi); q = n&3, stashed before d0 gets clobbered
	; by the IntToExtended/Fmul calls r's own computation needs.
	move.l			d0,d3
	move.l			d1,d4
	move.l			d2,d5
	lea.l			SinCosInvHalfPi,a0
	movem.l			(a0),d0/d1/d2
	jsr				NativeFmul
	jsr				NativeRoundToInt
	move.l			d0,d6
	and.l			#3,d6
	move.l			d6,SincosQ

	; r = x - n*(pi/2)
	jsr				NativeIntToExtended
	move.l			d0,d3
	move.l			d1,d4
	move.l			d2,d5
	lea.l			SinCosHalfPi,a0
	movem.l			(a0),d0/d1/d2
	jsr				NativeFmul
	move.l			d0,d3
	move.l			d1,d4
	move.l			d2,d5
	move.l			SincosX,d0
	move.l			SincosX+4,d1
	move.l			SincosX+8,d2
	jsr				NativeFsub
	move.l			d0,SincosR
	move.l			d1,SincosR+4
	move.l			d2,SincosR+8

	; t = r^2 (shared by both Horner loops below)
	move.l			d0,d3
	move.l			d1,d4
	move.l			d2,d5
	jsr				NativeFmul
	move.l			d0,SincosT
	move.l			d1,SincosT+4
	move.l			d2,SincosT+8

	; cos(r): result = CosC7; for n=6 downto 0, result := result*t +
	; CosCn. Same address-increment trick as NativeFexp's own Horner
	; loop (see there for why the constants are declared highest-
	; term-first in source, lowest-address-first in memory). 8-term
	; minimax (checklist #13), not the original 11-term Taylor/
	; Maclaurin series -- see cordic.asm's own header comment for why
	; CORDIC itself didn't pan out, and this file's own header comment
	; block above NativeFsincos for the minimax writeup.
	lea.l			CosC7,a0
	movem.l			(a0),d0/d1/d2
	move.l			d0,SincosCosR
	move.l			d1,SincosCosR+4
	move.l			d2,SincosCosR+8
	lea.l			CosC6,a0
	move.l			#6,SincosIterCount
	.CosLoop:
	move.l			SincosCosR,d0
	move.l			SincosCosR+4,d1
	move.l			SincosCosR+8,d2
	move.l			SincosT,d3
	move.l			SincosT+4,d4
	move.l			SincosT+8,d5
	jsr				NativeFmul
	move.l			d0,SincosCosR
	move.l			d1,SincosCosR+4
	move.l			d2,SincosCosR+8
	move.l			SincosCosR,d0
	move.l			SincosCosR+4,d1
	move.l			SincosCosR+8,d2
	movem.l			(a0),d3/d4/d5
	jsr				NativeFadd
	move.l			d0,SincosCosR
	move.l			d1,SincosCosR+4
	move.l			d2,SincosCosR+8
	adda.l			#12,a0
	subq.l			#1,SincosIterCount
	bpl.w			.CosLoop

	; sin(r) = r * (SinC7 Horner-evaluated the same way, 8-term minimax)
	lea.l			SinC7,a0
	movem.l			(a0),d0/d1/d2
	move.l			d0,SincosSinR
	move.l			d1,SincosSinR+4
	move.l			d2,SincosSinR+8
	lea.l			SinC6,a0
	move.l			#6,SincosIterCount
	.SinLoop:
	move.l			SincosSinR,d0
	move.l			SincosSinR+4,d1
	move.l			SincosSinR+8,d2
	move.l			SincosT,d3
	move.l			SincosT+4,d4
	move.l			SincosT+8,d5
	jsr				NativeFmul
	move.l			d0,SincosSinR
	move.l			d1,SincosSinR+4
	move.l			d2,SincosSinR+8
	move.l			SincosSinR,d0
	move.l			SincosSinR+4,d1
	move.l			SincosSinR+8,d2
	movem.l			(a0),d3/d4/d5
	jsr				NativeFadd
	move.l			d0,SincosSinR
	move.l			d1,SincosSinR+4
	move.l			d2,SincosSinR+8
	adda.l			#12,a0
	subq.l			#1,SincosIterCount
	bpl.w			.SinLoop
	move.l			SincosSinR,d0
	move.l			SincosSinR+4,d1
	move.l			SincosSinR+8,d2
	move.l			SincosR,d3
	move.l			SincosR+4,d4
	move.l			SincosR+8,d5
	jsr				NativeFmul
	move.l			d0,SincosSinR
	move.l			d1,SincosSinR+4
	move.l			d2,SincosSinR+8

	; Quadrant table: turn (sin(r),cos(r)) into (sin(x),cos(x)).
	; RESULT -- d0:d1:d2 = sin(x), d3:d4:d5 = cos(x).
	move.l			SincosQ,d6
	tst.l			d6
	beq.s			.Q0
	cmp.l			#1,d6
	beq.s			.Q1
	cmp.l			#2,d6
	beq.s			.Q2
	; Q3: sin(x) = -cos(r), cos(x) = sin(r)
	move.l			SincosCosR,d0
	move.l			SincosCosR+4,d1
	move.l			SincosCosR+8,d2
	bchg			#31,d0
	move.l			SincosSinR,d3
	move.l			SincosSinR+4,d4
	move.l			SincosSinR+8,d5
	rts
	.Q0:
	; sin(x) = sin(r), cos(x) = cos(r)
	move.l			SincosSinR,d0
	move.l			SincosSinR+4,d1
	move.l			SincosSinR+8,d2
	move.l			SincosCosR,d3
	move.l			SincosCosR+4,d4
	move.l			SincosCosR+8,d5
	rts
	.Q1:
	; sin(x) = cos(r), cos(x) = -sin(r)
	move.l			SincosCosR,d0
	move.l			SincosCosR+4,d1
	move.l			SincosCosR+8,d2
	move.l			SincosSinR,d3
	move.l			SincosSinR+4,d4
	move.l			SincosSinR+8,d5
	bchg			#31,d3
	rts
	.Q2:
	; sin(x) = -sin(r), cos(x) = -cos(r)
	move.l			SincosSinR,d0
	move.l			SincosSinR+4,d1
	move.l			SincosSinR+8,d2
	bchg			#31,d0
	move.l			SincosCosR,d3
	move.l			SincosCosR+4,d4
	move.l			SincosCosR+8,d5
	bchg			#31,d3
	rts

SinCosHalfPi	dc.l	$3fff0000,$c90fdaa2,$2168c235	; pi/2
SinCosInvHalfPi	dc.l	$3ffe0000,$a2f9836e,$4e44152a	; 2/pi
SincosX			dc.l	0,0,0
SincosQ			dc.l	0
SincosR			dc.l	0,0,0
SincosT			dc.l	0,0,0
SincosSinR		dc.l	0,0,0
SincosCosR		dc.l	0,0,0
SincosIterCount	dc.l	0
; 8-term minimax (checklist #13, Remez exchange in Python against an
; exact-Decimal reference, 60+ digits of precision) replaces the
; original 11-term Taylor/Maclaurin series -- the whole interval is
; [0,(pi/4)^2] (t=r^2), narrow and symmetric enough that Chebyshev-
; economizing the Taylor series ALREADY lands within a few percent of
; the true minimax error (cross-checked: a full Remez run gave the
; same term count and matched the economized error to 4 significant
; figures), so minimax genuinely saves 3 terms here, not an illusion
; from a looser tolerance. Verified against dec_sin/dec_cos at 60
; digits, 20000+ random |x| up to 1000 plus the r=0/r=+-pi/4
; boundary cases, before writing any assembly -- worst case ~0.3 ULP
; of this format's 64-bit mantissa, comfortably inside the margin
; #10's own 11-term series used.
SinC7		dc.l	$bfd60000,$d54dec22,$efc09046	; -minimax c7
SinC6		dc.l	$3fde0000,$b0903e76,$77620912	; +minimax c6
SinC5		dc.l	$bfe50000,$d7322938,$09aac142	; -minimax c5
SinC4		dc.l	$3fec0000,$b8ef1d29,$89de95d7	; +minimax c4
SinC3		dc.l	$bff20000,$d00d00d0,$0c443bee	; -minimax c3
SinC2		dc.l	$3ff80000,$88888888,$88884e63	; +minimax c2
SinC1		dc.l	$bffc0000,$aaaaaaaa,$aaaaaa8f	; -minimax c1
SinC0		dc.l	$3fff0000,$80000000,$00000000	; +minimax c0
CosC7		dc.l	$bfda0000,$c7bb1c07,$ddb67542	; -minimax c7
CosC6		dc.l	$3fe20000,$8f74b693,$20d77422	; +minimax c6
CosC5		dc.l	$bfe90000,$93f27b94,$17a339db	; -minimax c5
CosC4		dc.l	$3fef0000,$d00d00cd,$8f46c379	; +minimax c4
CosC3		dc.l	$bff50000,$b60b60b6,$09d05469	; -minimax c3
CosC2		dc.l	$3ffa0000,$aaaaaaaa,$aaa9b3c4	; +minimax c2
CosC1		dc.l	$bffd0000,$ffffffff,$ffffff18	; -minimax c1
CosC0		dc.l	$3ffe0000,$ffffffff,$ffffffff	; +minimax c0


;
; Native atan(x) (checklist #10): the one function in this row needing
; a genuinely new algorithm rather than a derivation from fexp/flogn/
; fsincos -- atan's own Gregory series (x - x^3/3 + x^5/5 - ...)
; converges far too slowly to use directly (geometric-ish decay by x^2
; per term, not factorial like sin/cos/exp's series), so two range-
; reduction identities are chained before any series is evaluated:
;
;   1. atan is odd: work with |x|, reapply the sign at the very end.
;   2. |x| > 1: atan(x) = pi/2 - atan(1/x), reducing to |x| <= 1.
;   3. |x| > tan(pi/8) (= sqrt(2)-1): atan(x) = pi/4 + atan((x-1)/(x+1)),
;      reducing to |x| <= tan(pi/8) ~= 0.41421356 (step 3's (x-1)/(x+1)
;      is always <= 0 for x in (tan(pi/8),1], but still bounded in
;      magnitude by tan(pi/8) -- verified in Python alongside the term
;      count below).
;
; After both reductions, |x| <= tan(pi/8) and the Gregory series
; (rewritten as x * sum_k (-1)^k*x^(2k)/(2k+1), Horner-evaluated in
; t=x^2, same shape as every other row-#10 series) needs 25 terms (C0
; through C24) -- verified in Python (exact Decimal arithmetic, 2000+
; samples spanning the whole reduced range including its x=tan(pi/8)
; edge) to bring the series' OWN truncation error below 2^-64 there,
; with the usual small safety margin over the 23 terms Python found
; were the actual minimum. This is a longer table than fexp/flogn/
; sincos needed (16/13/11 terms respectively) because the Gregory
; series has no factorial in its denominator -- just 2k+1 -- so it
; decays only geometrically (~0.17 per term here) rather than
; super-exponentially; a real cost of this identity, not a mistake.
;
; pi/2 reuses SinCosHalfPi (NativeFsincos, above) rather than a second
; copy, same reasoning as NativeFlogn reusing NativeFexp's ExpLn2 --
; verified in Python that AtanConstQuarterPi below is bit-for-bit the
; same mantissa as SinCosHalfPi with the exponent field one lower
; (pi/4 = pi/2 / 2, an exact halving), so only ONE extra pi-derived
; constant (pi/4) needed declaring here.
;
; The two "is x bigger than this constant" tests (step 2 against 1.0,
; step 3 against tan(pi/8)) are a plain 3-word unsigned lexicographic
; compare -- valid because both operands are positive, finite,
; normalized extended values (reserved bits zero), so bit-pattern order
; equals numeric order exactly like IEEE single/double. Duplicated
; rather than factored into a shared compare routine: there are exactly
; two call sites, both inside this one routine, matching the "copy the
; ten lines when a second caller shows up, don't speculatively
; abstract" rule as literally as it gets.
;
; INPUTS
;	d0 -- Sign(1):exponent(15):reserved(16). Must be an ordinary
;	      (finite, nonzero, non-NaN/Inf) value -- callers (fatan.asm)
;	      are responsible for the 0/Inf/NaN special cases before
;	      calling this.
;	d1 -- Mantissa bits 63-32 (explicit integer bit at bit 31).
;	d2 -- Mantissa bits 31-0.
;
; RESULT
;	d0 -- Sign(1):exponent(15):reserved(16) of atan(x).
;	d1 -- Mantissa bits 63-32 of atan(x).
;	d2 -- Mantissa bits 31-0 of atan(x).
;
NativeFatan
	; Split off the sign (atan is odd -- reapplied at the very end) and
	; keep working with |x| only, stashed in memory since every jsr
	; below clobbers d0-d5 freely and d6 isn't preserved across one
	; either (see this file's own header comment).
	move.l			d0,d6
	and.l			#$80000000,d6
	move.l			d6,AtanSign
	and.l			#$7fffffff,d0
	move.l			d0,AtanX
	move.l			d1,AtanX+4
	move.l			d2,AtanX+8
	moveq			#0,d6
	move.l			d6,AtanRecip
	move.l			d6,AtanHalf

	; recip = |x| > 1.0 ?
	move.l			AtanX,d0
	cmp.l			AtanConstOne,d0
	bhi.s			.Recip
	blo.s			.NoRecip
	move.l			AtanX+4,d1
	cmp.l			AtanConstOne+4,d1
	bhi.s			.Recip
	blo.s			.NoRecip
	move.l			AtanX+8,d2
	cmp.l			AtanConstOne+8,d2
	bls.s			.NoRecip
	.Recip:
	moveq			#1,d6
	move.l			d6,AtanRecip
	.NoRecip:

	tst.l			AtanRecip
	beq.s			.NoRecipDiv

	; x := 1.0/x
	lea.l			AtanConstOne,a0
	movem.l			(a0),d0/d1/d2
	move.l			AtanX,d3
	move.l			AtanX+4,d4
	move.l			AtanX+8,d5
	jsr				NativeFdiv
	move.l			d0,AtanX
	move.l			d1,AtanX+4
	move.l			d2,AtanX+8
	.NoRecipDiv:

	; half = |x| > tan(pi/8) ?
	move.l			AtanX,d0
	cmp.l			AtanConstTanPi8,d0
	bhi.s			.Half
	blo.s			.NoHalf
	move.l			AtanX+4,d1
	cmp.l			AtanConstTanPi8+4,d1
	bhi.s			.Half
	blo.s			.NoHalf
	move.l			AtanX+8,d2
	cmp.l			AtanConstTanPi8+8,d2
	bls.s			.NoHalf
	.Half:
	moveq			#1,d6
	move.l			d6,AtanHalf
	.NoHalf:

	tst.l			AtanHalf
	beq.s			.NoHalfDiv

	; x := (x-1)/(x+1)
	move.l			AtanX,d0
	move.l			AtanX+4,d1
	move.l			AtanX+8,d2
	lea.l			AtanConstOne,a0
	movem.l			(a0),d3/d4/d5
	jsr				NativeFsub
	move.l			d0,AtanNum
	move.l			d1,AtanNum+4
	move.l			d2,AtanNum+8
	move.l			AtanX,d0
	move.l			AtanX+4,d1
	move.l			AtanX+8,d2
	lea.l			AtanConstOne,a0
	movem.l			(a0),d3/d4/d5
	jsr				NativeFadd
	move.l			d0,d3
	move.l			d1,d4
	move.l			d2,d5
	move.l			AtanNum,d0
	move.l			AtanNum+4,d1
	move.l			AtanNum+8,d2
	jsr				NativeFdiv
	move.l			d0,AtanX
	move.l			d1,AtanX+4
	move.l			d2,AtanX+8
	.NoHalfDiv:

	; t = x*x
	move.l			AtanX,d0
	move.l			AtanX+4,d1
	move.l			AtanX+8,d2
	move.l			d0,d3
	move.l			d1,d4
	move.l			d2,d5
	jsr				NativeFmul
	move.l			d0,AtanT
	move.l			d1,AtanT+4
	move.l			d2,AtanT+8

	; Horner evaluation: result = C12; for n=11 downto 0,
	; result := result*t + Cn. Same address-increment trick as
	; NativeFexp's own Horner loop (see there for why the constants are
	; declared highest-term-first in source, lowest-address-first in
	; memory). 13-term minimax (checklist #13, Remez exchange in
	; Python), not the original 25-term Taylor/Gregory series -- see
	; this file's own AtanC12 comment below for the writeup. Almost
	; half the terms: the Gregory series decays only geometrically (no
	; factorial), so minimax has far more room to improve on it than
	; it did for #13's sin/cos row (11->8 terms there, 25->13 here).
	lea.l			AtanC12,a0
	movem.l			(a0),d0/d1/d2
	move.l			d0,AtanResult
	move.l			d1,AtanResult+4
	move.l			d2,AtanResult+8
	lea.l			AtanC11,a0
	move.l			#11,AtanIterCount
	.HornerLoop:
	move.l			AtanResult,d0
	move.l			AtanResult+4,d1
	move.l			AtanResult+8,d2
	move.l			AtanT,d3
	move.l			AtanT+4,d4
	move.l			AtanT+8,d5
	jsr				NativeFmul
	move.l			d0,AtanResult
	move.l			d1,AtanResult+4
	move.l			d2,AtanResult+8
	move.l			AtanResult,d0
	move.l			AtanResult+4,d1
	move.l			AtanResult+8,d2
	movem.l			(a0),d3/d4/d5
	jsr				NativeFadd
	move.l			d0,AtanResult
	move.l			d1,AtanResult+4
	move.l			d2,AtanResult+8
	adda.l			#12,a0
	subq.l			#1,AtanIterCount
	bpl.w			.HornerLoop

	; result = x * poly
	move.l			AtanX,d0
	move.l			AtanX+4,d1
	move.l			AtanX+8,d2
	move.l			AtanResult,d3
	move.l			AtanResult+4,d4
	move.l			AtanResult+8,d5
	jsr				NativeFmul
	move.l			d0,AtanResult
	move.l			d1,AtanResult+4
	move.l			d2,AtanResult+8

	; + pi/4, if the half-angle identity was used
	tst.l			AtanHalf
	beq.s			.NoHalfAdd
	lea.l			AtanConstQuarterPi,a0
	movem.l			(a0),d0/d1/d2
	move.l			AtanResult,d3
	move.l			AtanResult+4,d4
	move.l			AtanResult+8,d5
	jsr				NativeFadd
	move.l			d0,AtanResult
	move.l			d1,AtanResult+4
	move.l			d2,AtanResult+8
	.NoHalfAdd:

	; pi/2 - result, if the reciprocal identity was used
	tst.l			AtanRecip
	beq.s			.NoRecipSub
	lea.l			SinCosHalfPi,a0
	movem.l			(a0),d0/d1/d2
	move.l			AtanResult,d3
	move.l			AtanResult+4,d4
	move.l			AtanResult+8,d5
	jsr				NativeFsub
	move.l			d0,AtanResult
	move.l			d1,AtanResult+4
	move.l			d2,AtanResult+8
	.NoRecipSub:

	; Reapply the original sign (atan is odd).
	move.l			AtanResult,d0
	move.l			AtanSign,d6
	or.l			d6,d0
	move.l			AtanResult+4,d1
	move.l			AtanResult+8,d2
	rts

AtanConstOne		dc.l	$3fff0000,$80000000,$00000000	; 1.0
AtanConstTanPi8		dc.l	$3ffd0000,$d413cccf,$e7799211	; tan(pi/8)
AtanConstQuarterPi	dc.l	$3ffe0000,$c90fdaa2,$2168c235	; pi/4
AtanSign		dc.l	0
AtanRecip		dc.l	0
AtanHalf		dc.l	0
AtanX			dc.l	0,0,0
AtanNum			dc.l	0,0,0
AtanT			dc.l	0,0,0
AtanResult		dc.l	0,0,0
AtanIterCount		dc.l	0
; 13-term minimax (checklist #13, Remez exchange in Python against an
; exact-Decimal reference, 60+ digit precision) replaces the original
; 25-term Gregory/Taylor series -- same reduced range (t=x^2, x in
; [0,tan(pi/8)]) the reciprocal/half-angle reduction above already
; produces, same Horner-loop shape. Verified end-to-end (full
; reduction pipeline, 30000+ random |x| up to 1e6 plus 0/1/huge/tiny
; boundary cases) against dec_atan at 90 digits: worst case ~0.003 ULP
; of this format's 64-bit mantissa -- comfortably inside the margin
; #10's own 25-term series used, with far more room to spare than
; sin/cos's 8-term minimax had, because the Gregory series' lack of a
; factorial in its denominator gives minimax much more slack to work
; with here.
AtanC12		dc.l	$3ff80000,$f84b3df1,$a908187b	; +minimax c12
AtanC11		dc.l	$bffa0000,$88edd8d7,$18cea276	; -minimax c11
AtanC10		dc.l	$3ffa0000,$b86098f0,$69d464ca	; +minimax c10
AtanC9		dc.l	$bffa0000,$d5b8a4e6,$fee157aa	; -minimax c9
AtanC8		dc.l	$3ffa0000,$f0b7eaf7,$f6dcfb53	; +minimax c8
AtanC7		dc.l	$bffb0000,$88862901,$1bfe717c	; -minimax c7
AtanC6		dc.l	$3ffb0000,$9d89b5c6,$6031cc92	; +minimax c6
AtanC5		dc.l	$bffb0000,$ba2e8a4a,$bdd571d2	; -minimax c5
AtanC4		dc.l	$3ffb0000,$e38e38db,$0218b978	; +minimax c4
AtanC3		dc.l	$bffc0000,$92492492,$38f1d7fe	; -minimax c3
AtanC2		dc.l	$3ffc0000,$cccccccc,$ccacde09	; +minimax c2
AtanC1		dc.l	$bffd0000,$aaaaaaaa,$aaaa9e4b	; -minimax c1
AtanC0		dc.l	$3ffe0000,$ffffffff,$ffffffff	; +minimax c0


;
; Native asin(x) (checklist #10): no new algorithm needed, the last
; piece of this row -- asin(x) = atan(x/sqrt(1-x^2)), composed entirely
; from NativeFsub/NativeFadd/NativeFmul/NativeFsqrt/NativeFdiv/
; NativeFatan, all already landed. facos.asm derives its own result
; from this same routine (acos(x) = pi/2 - asin(x)), the way ftan.asm
; derives from NativeFsincos rather than needing its own wrapper -- so
; there's no NativeFacos here, same reasoning.
;
; 1-x^2 is deliberately NOT computed as a single multiply-then-
; subtract -- `x*x` then `1 - x*x` loses precision catastrophically as
; |x| -> 1 (subtracting two nearly-equal quantities). Factored instead
; as `(1-x)*(1+x)`: algebraically identical, but neither sub-
; expression is a near-cancellation (`1-x` and `1+x` are both well-
; conditioned for |x| < 1), so no precision is lost before the sqrt
; even gets a chance to amplify it. Verified in Python before writing
; any assembly: the naive `1-x*x` form loses ~4-5 bits near |x|->1
; (worst abs error ~4.7e-15 across 200000 random samples, double
; precision), while `(1-x)*(1+x)` brings the SAME test down to ~1 ULP
; (~2.2e-16) -- not a hypothetical difference, a real one this row's
; "verify, don't guess" rule exists to catch before it ships.
;
; INPUTS
;	d0 -- Sign(1):exponent(15):reserved(16). Must be an ordinary
;	      (finite, nonzero, non-NaN/Inf) value with |x| < 1 --
;	      callers (fasin.asm/facos.asm) are responsible for the
;	      0/+-1/out-of-domain/Inf/NaN special cases before calling
;	      this.
;	d1 -- Mantissa bits 63-32 (explicit integer bit at bit 31).
;	d2 -- Mantissa bits 31-0.
;
; RESULT
;	d0 -- Sign(1):exponent(15):reserved(16) of asin(x).
;	d1 -- Mantissa bits 63-32 of asin(x).
;	d2 -- Mantissa bits 31-0 of asin(x).
;
NativeFasin
	move.l			d0,AsinX
	move.l			d1,AsinX+4
	move.l			d2,AsinX+8

	; 1-x
	lea.l			AsinConstOne,a0
	movem.l			(a0),d0/d1/d2
	move.l			AsinX,d3
	move.l			AsinX+4,d4
	move.l			AsinX+8,d5
	jsr				NativeFsub
	move.l			d0,AsinOneMinusX
	move.l			d1,AsinOneMinusX+4
	move.l			d2,AsinOneMinusX+8

	; 1+x
	lea.l			AsinConstOne,a0
	movem.l			(a0),d0/d1/d2
	move.l			AsinX,d3
	move.l			AsinX+4,d4
	move.l			AsinX+8,d5
	jsr				NativeFadd

	; (1-x)*(1+x)
	move.l			d0,d3
	move.l			d1,d4
	move.l			d2,d5
	move.l			AsinOneMinusX,d0
	move.l			AsinOneMinusX+4,d1
	move.l			AsinOneMinusX+8,d2
	jsr				NativeFmul

	; sqrt((1-x)*(1+x))
	jsr				NativeFsqrt

	; x/sqrt(...)
	move.l			d0,d3
	move.l			d1,d4
	move.l			d2,d5
	move.l			AsinX,d0
	move.l			AsinX+4,d1
	move.l			AsinX+8,d2
	jsr				NativeFdiv

	; asin(x) = atan(x/sqrt((1-x)*(1+x)))
	jsr				NativeFatan
	rts

AsinConstOne	dc.l	$3fff0000,$80000000,$00000000	; 1.0
AsinX			dc.l	0,0,0
AsinOneMinusX	dc.l	0,0,0
