;
; Shared CORDIC infrastructure (checklist #13): circular-mode rotation
; for the sin/cos/tan/sincos family, replacing #10's Horner-series
; NativeFsincos internals with shift-add-only iteration -- the whole
; point of CORDIC is trading MUL64 (expensive on a 68k with no fast
; hardware multiply) for plain shifts and adds. Everything here works
; in a SEPARATE, pure fixed-point format from the rest of the codebase
; -- NOT the sign:exponent:mantissa extended layout #4 established --
; converting at the boundary (entry/exit of the rotation) exactly like
; ExtendedToDouble/DoubleToExtended already do for the double-precision
; boundary.
;
; FIXED-POINT FORMAT: "Fixed96" -- a 96-bit (3 longword) two's-
; complement integer representing value = int96 / 2^95 ("Q1.95": one
; sign bit, 95 fraction bits, |value| < 1). This covers every value
; the circular kernel touches: the reduced angle r (|r| <= pi/4, from
; NativeFsincos's existing quadrant reduction) going in, and cos(r)/
; sin(r) (both < 1 in magnitude) coming out -- verified in Python
; against an exact Decimal reference, 62 iterations converging to
; within ~4 ULP of this format's 64-bit mantissa precision (using a
; 160-bit scratch buffer during the shift/add so the 64-bit result
; gets ~32 bits of guard precision during the iteration, same
; "compute wider, round once at the end" principle any multi-step
; chain in this codebase already relies on).
;
; The atan(2^-i) table (CordicAtan0 below) is declared ASCENDING (i=0
; first), unlike every Horner table elsewhere in this codebase
; (declared highest-term-first for a simple forward address walk) --
; CORDIC isn't a Horner evaluation, it's a single linear pass over
; increasing i, so ascending-in-source IS the natural forward-address
; order here; flagged explicitly since it's a real, deliberate
; deviation from the rest of #10/#13's own convention, not an
; oversight.
;
; d7 is NOT available to anything here (see nativemath.asm's header
; comment -- it's INSTRUCTION, read by GETREGISTER after any handler
; returns). The iteration counter (CordicI below) lives in memory,
; same reasoning as every other native-math loop in this codebase.
;

;
; CordicShiftExtract: given a 160-bit buffer (\1, 5 contiguous
; longwords -- the caller has ALREADY filled the first 2 words with
; either all-zero (unsigned/zero-extend case) or all-one (signed,
; sign-extend case) and the last 3 words with the 96-bit value being
; shifted) and a shift amount 0-64 in \2, extracts the 96-bit
; arithmetic-right-shift-by-\2 result into \3 (3 contiguous longwords).
;
; Derivation: shifting a value right by k and keeping the low 96 bits
; is the SAME bit pattern as reading a 96-bit window of the (already
; extension-padded) 160-bit buffer starting bit offset (64-k) from the
; buffer's own start -- the extension words supply exactly the bits
; that "shift in" from the left, for free, with no separate sign-
; extension step needed after the read. Using three fixed-WIDTH-32
; bfextu reads with only the OFFSET varying (not the width) keeps this
; to three single-instruction extracts -- 68020's bfextu supports a
; register-specified offset on a memory operand that reaches well
; beyond the nominal base operand's own size, which is exactly what
; lets a 20-byte buffer be addressed this way at all.
;
; Always writes its result to the fixed CordicShiftOut scratch label
; (not a macro parameter) -- some callers want the result written
; through an address register ((a0)) or at a non-label offset
; (CordicBuf+12), neither of which vasm's macro substitution can
; glue a literal "+4"/"+8" onto (tried it: "trailing garbage in
; operand" -- a macro parameter that expands to "(a0)" or
; "CordicBuf+12" doesn't accept a further "+4" appended to it the way
; a plain label does). Callers needing the result somewhere else copy
; it out of CordicShiftOut themselves, same as any other routine
; here returning through a fixed scratch cell.
;
; INPUTS
;	\1 -- Label of a 5-longword (20-byte) buffer: 2 extension words
;	      (caller-filled) then the 96-bit value (3 words).
;	\2 -- Shift amount, 0-64, in a data register (NOT d7).
;
; RESULT
;	CordicShiftOut -- the shifted 96-bit (3-longword) result.
;
; Clobbers d0/d1/a0. \2's register is left unchanged.
;
CordicShiftExtract macro
	moveq			#64,d0
	sub.l			\2,d0
	lea.l			\1,a0
	bfextu			(a0){d0:32},d1
	move.l			d1,CordicShiftOut
	add.l			#32,d0
	bfextu			(a0){d0:32},d1
	move.l			d1,CordicShiftOut+4
	add.l			#32,d0
	bfextu			(a0){d0:32},d1
	move.l			d1,CordicShiftOut+8
endm


;
; 96-bit two's-complement add/subtract, \1 := \1 +/- \2 (both 3-word
; labels). MOVE doesn't touch the CCR, so the X flag SUBX/ADDX needs
; survives the intervening moves between words untouched -- the same
; reasoning any multi-word 68k add/sub chain relies on.
;
Add96 macro
	move.l			\2+8,d0
	move.l			\1+8,d1
	add.l			d0,d1
	move.l			d1,\1+8
	move.l			\2+4,d0
	move.l			\1+4,d1
	addx.l			d0,d1
	move.l			d1,\1+4
	move.l			\2,d0
	move.l			\1,d1
	addx.l			d0,d1
	move.l			d1,\1
endm

Sub96 macro
	move.l			\2+8,d0
	move.l			\1+8,d1
	sub.l			d0,d1
	move.l			d1,\1+8
	move.l			\2+4,d0
	move.l			\1+4,d1
	subx.l			d0,d1
	move.l			d1,\1+4
	move.l			\2,d0
	move.l			\1,d1
	subx.l			d0,d1
	move.l			d1,\1
endm


;
; Converts an extended-format operand (|value| < 1, verified by every
; caller before this is reached -- same precondition #10's own native
; routines already place on their callers) into Fixed96.
;
; m (the 64-bit mantissa, explicit bit at bit 31 of d1) already IS the
; unsigned magnitude placed with 32 bits of trailing zero padding --
; "m << 32" -- for free, just by putting d1/d2 in the low 2 of 3
; value words and 0 in the third. Fixed96's magnitude is then that
; padded value shifted right by (16383 - biased_exp) -- verified by
; hand (see this op's own design notes): value = m/2^63 * 2^rawexp,
; and we want round(value * 2^95) = m * 2^(32+rawexp) = (m<<32) >>
; (-rawexp), with -rawexp = 16383-biased_exp exactly. Negated at the
; end if the operand was negative -- d1/d2 are always the unsigned
; magnitude regardless of sign, same convention #4 established
; everywhere else.
;
; Shift amounts over 64 (only reachable for a value smaller than
; 2^-64, i.e. already far below this kernel's own ~4 ULP accuracy
; floor) are clamped to a zero result rather than read out of the
; shift buffer's valid range -- same spirit as NativeRoundToInt's own
; documented "not hardened beyond the range callers actually produce".
;
; INPUTS
;	d0 -- Sign(1):exponent(15):reserved(16). |value| < 1.
;	d1 -- Mantissa bits 63-32 (explicit integer bit at bit 31).
;	d2 -- Mantissa bits 31-0.
;	a0 -- Destination: a 3-longword Fixed96 buffer.
;
; a1 (not a0) carries the destination pointer across the macro call
; below -- CordicShiftExtract's own "lea.l \1,a0" clobbers a0, and
; (separately) its shift-offset arithmetic clobbers d0 too, so the
; sign bit is latched into d6 up front rather than re-tested from d0
; afterward. Both caught by the fsin(0.25) bench vector silently
; writing its shifted result into CordicBuf instead of the real
; destination (a0 no longer pointed at it) while leaving the real
; destination untouched at its stale/zero value.
NativeExtendedToFixed96
	move.l			a0,a1
	moveq			#0,d6
	btst			#31,d0
	beq.s			.NotNeg
	moveq			#1,d6
	.NotNeg:
	bfextu			d0{1:15},d3
	beq.w			.Zero
	move.l			#16383,d4
	sub.l			d3,d4			; d4 = shift = -rawexp (>= 1)
	cmp.l			#64,d4
	bgt.w			.Zero

	moveq			#0,d3
	move.l			d3,CordicBuf
	move.l			d3,CordicBuf+4
	move.l			d1,CordicBuf+8
	move.l			d2,CordicBuf+12
	move.l			d3,CordicBuf+16
	CordicShiftExtract	CordicBuf,d4
	move.l			CordicShiftOut,(a1)
	move.l			CordicShiftOut+4,4(a1)
	move.l			CordicShiftOut+8,8(a1)

	tst.l			d6
	beq.w			.Done
	moveq			#0,d3
	move.l			d3,d1
	move.l			(a1),d4
	sub.l			d4,d1
	move.l			d1,(a1)
	move.l			d3,d1
	move.l			4(a1),d4
	subx.l			d4,d1
	move.l			d1,4(a1)
	move.l			d3,d1
	move.l			8(a1),d4
	subx.l			d4,d1
	move.l			d1,8(a1)
	rts

	.Zero:
	moveq			#0,d3
	move.l			d3,(a0)
	move.l			d3,4(a0)
	move.l			d3,8(a0)
	.Done:
	rts


;
; Converts a Fixed96 value back to extended format. Takes the
; magnitude's sign off first (two's-complement negate, same as every
; other native routine's own sign-handling), then normalizes: finds
; the highest set bit (bfffo, word by word -- the sign word's own top
; bit is always 0 for a valid |value|<1 input, so bfffo on a nonzero
; high word always returns 1-31, never 0, matching this), extracts
; the 64 bits starting there as the mantissa (its own top bit is 1 by
; construction, satisfying the explicit-bit convention), and sets
; biased_exp = 16383 - (that bit's distance from the sign bit) --
; verified by hand against two worked examples (value=0.5 and
; value=0.25) before writing this, same as the shift-amount derivation
; above.
;
; INPUTS
;	a0 -- A 3-longword Fixed96 value.
;
; RESULT
;	d0 -- Sign(1):exponent(15):reserved(16).
;	d1 -- Mantissa bits 63-32 (explicit integer bit at bit 31).
;	d2 -- Mantissa bits 31-0.
;
NativeFixed96ToExtended
	moveq			#0,d6
	move.l			(a0),d3
	move.l			4(a0),d4
	move.l			8(a0),d5
	tst.l			d3
	bne.s			.NotZeroHi
	tst.l			d4
	bne.s			.NotZeroHi
	tst.l			d5
	beq.w			.Zero
	.NotZeroHi:

	tst.l			d3
	bpl.s			.Positive
	moveq			#1,d6			; sign flag
	moveq			#0,d0
	move.l			d0,d1
	sub.l			d5,d1
	move.l			d0,d2
	subx.l			d4,d2
	move.l			d0,d0
	subx.l			d3,d0
	move.l			d0,d3
	move.l			d2,d4
	move.l			d1,d5
	.Positive:
	move.l			d3,CordicBuf
	move.l			d4,CordicBuf+4
	move.l			d5,CordicBuf+8
	moveq			#0,d3
	move.l			d3,CordicBuf+12
	move.l			d3,CordicBuf+16

	move.l			CordicBuf,d0
	bne.s			.HiNonZero
	move.l			CordicBuf+4,d0
	bne.s			.MidNonZero
	bfffo			CordicBuf+8{0:32},d3
	add.l			#64,d3			; lz = 64 + bfffo(lo)
	bra.s			.GotLz
	.MidNonZero:
	bfffo			CordicBuf+4{0:32},d3
	add.l			#32,d3			; lz = 32 + bfffo(mid)
	bra.s			.GotLz
	.HiNonZero:
	bfffo			CordicBuf{0:32},d3	; lz = bfffo(hi), 1..31
	.GotLz:

	move.l			#16383,d4
	sub.l			d3,d4			; d4 = biased_exp
	lsl.l			#8,d4
	lsl.l			#8,d4			; into bits 30:16

	; Mantissa: the 64-bit window of CordicBuf starting at bit offset
	; lz (d3) -- NOT CordicShiftExtract's own "64-\2" offset formula,
	; which is for a right-shift of a buffer with its 2 pad words
	; BEFORE the value (NativeExtendedToFixed96's and
	; CordicRotateCircular's own layout). Here the value sits FIRST
	; (CordicBuf/+4/+8) with the 2 pad words AFTER (+12/+16) -- a
	; left-shift-style read, offset = lz directly. Tried forcing this
	; through CordicShiftExtract first; it produced an all-zero
	; mantissa for every nonzero input (caught immediately by the
	; fsin(0.25) bench vector) because the two buffer shapes don't
	; share one offset formula -- this is written out separately
	; rather than bent to fit, per CLAUDE.md's own "don't speculatively
	; abstract two different shapes into one macro" guidance.
	move.l			d3,d0
	lea.l			CordicBuf,a0
	bfextu			(a0){d0:32},d1
	add.l			#32,d0
	bfextu			(a0){d0:32},d2

	move.l			d4,d0

	tst.l			d6
	beq.s			.Done
	bset			#31,d0
	.Done:
	rts

	.Zero:
	moveq			#0,d0
	moveq			#0,d1
	moveq			#0,d2
	rts


;
; Circular-mode CORDIC rotation: given the reduced angle z0 (Fixed96,
; |z0| <= pi/4, left in CordicZ by the caller) and the pre-scaled
; starting vector (1/K, 0) (set up by the caller as CordicX/CordicY),
; iterates z toward 0, accumulating the rotation into x/y -- the
; standard circular-CORDIC rotation-mode recurrence, 62 iterations
; (verified in Python against an exact Decimal reference: ~4 ULP of
; this format's 64-bit mantissa, well past where more iterations stop
; helping). Result: CordicX = cos(z0), CordicY = sin(z0), exactly (no
; further gain correction needed -- 1/K was already baked into the
; starting x).
;
; No inputs/outputs in registers at all -- this operates purely on the
; CordicX/CordicY/CordicZ/CordicI memory cells, which the caller reads
; back directly. Kept this way (rather than threading state through
; registers) because every iteration already needs d0-d6 as shift/add
; scratch -- there's nothing left to carry state in anyway.
;
CordicRotateCircular
	moveq			#0,d0
	move.l			d0,CordicI
	lea.l			CordicAtan0,a1

	.Loop:
	move.l			CordicI,d6

	; xshift = x >> i  (x never goes negative for |z0|<=pi/4, but
	; test fresh anyway rather than assume it -- cheap, and this
	; isn't the kind of invariant worth trusting without checking).
	move.l			CordicX,d0
	bpl.s			.XPos
	moveq			#-1,d0
	bra.s			.XExtDone
	.XPos:
	moveq			#0,d0
	.XExtDone:
	move.l			d0,CordicBuf
	move.l			d0,CordicBuf+4
	move.l			CordicX,CordicBuf+8
	move.l			CordicX+4,CordicBuf+12
	move.l			CordicX+8,CordicBuf+16
	CordicShiftExtract	CordicBuf,d6
	move.l			CordicShiftOut,CordicXShift
	move.l			CordicShiftOut+4,CordicXShift+4
	move.l			CordicShiftOut+8,CordicXShift+8

	; yshift = y >> i
	move.l			CordicY,d0
	bpl.s			.YPos
	moveq			#-1,d0
	bra.s			.YExtDone
	.YPos:
	moveq			#0,d0
	.YExtDone:
	move.l			d0,CordicBuf
	move.l			d0,CordicBuf+4
	move.l			CordicY,CordicBuf+8
	move.l			CordicY+4,CordicBuf+12
	move.l			CordicY+8,CordicBuf+16
	CordicShiftExtract	CordicBuf,d6
	move.l			CordicShiftOut,CordicYShift
	move.l			CordicShiftOut+4,CordicYShift+4
	move.l			CordicShiftOut+8,CordicYShift+8

	tst.l			CordicZ
	bmi.w			.Neg

	; z >= 0: x -= yshift; y += xshift; z -= table[i]
	Sub96			CordicX,CordicYShift
	Add96			CordicY,CordicXShift
	move.l			8(a1),d0
	move.l			CordicZ+8,d1
	sub.l			d0,d1
	move.l			d1,CordicZ+8
	move.l			4(a1),d0
	move.l			CordicZ+4,d1
	subx.l			d0,d1
	move.l			d1,CordicZ+4
	move.l			(a1),d0
	move.l			CordicZ,d1
	subx.l			d0,d1
	move.l			d1,CordicZ
	bra.w			.Next

	.Neg:
	; z < 0: x += yshift; y -= xshift; z += table[i]
	Add96			CordicX,CordicYShift
	Sub96			CordicY,CordicXShift
	move.l			8(a1),d0
	move.l			CordicZ+8,d1
	add.l			d0,d1
	move.l			d1,CordicZ+8
	move.l			4(a1),d0
	move.l			CordicZ+4,d1
	addx.l			d0,d1
	move.l			d1,CordicZ+4
	move.l			(a1),d0
	move.l			CordicZ,d1
	addx.l			d0,d1
	move.l			d1,CordicZ

	.Next:
	adda.l			#12,a1
	addq.l			#1,CordicI
	move.l			CordicI,d0
	cmp.l			#62,d0
	blt.w			.Loop
	rts

CordicBuf		dc.l	0,0,0,0,0
CordicShiftOut	dc.l	0,0,0
CordicX			dc.l	0,0,0
CordicY			dc.l	0,0,0
CordicZ			dc.l	0,0,0
CordicXShift	dc.l	0,0,0
CordicYShift	dc.l	0,0,0
CordicI			dc.l	0

; 1/K (K = CORDIC circular gain for 62 iterations), Q1.95 Fixed96.
CordicInvK		dc.l	$4dba76d4,$21af2d33,$fafc8496

; atan(2^-i), i=0..61, Q1.95 Fixed96 -- ASCENDING (see header comment).
CordicAtan0		dc.l	$6487ed51,$10b4611a,$62633146
CordicAtan1		dc.l	$3b58ce0a,$c3769ed1,$5bf9117b
CordicAtan2		dc.l	$1f5b75f9,$2c80dd62,$adb8f3df
CordicAtan3		dc.l	$0feadd4d,$5617b6e3,$2c89798a
CordicAtan4		dc.l	$07fd56ed,$cb3f7a71,$b6593c97
CordicAtan5		dc.l	$03ffaab7,$752ec495,$09de75de
CordicAtan6		dc.l	$01fff555,$bbb729ab,$77cf18ad
CordicAtan7		dc.l	$00fffeaa,$adddd4b9,$68062352
CordicAtan8		dc.l	$007fffd5,$556eeedc,$a5d8957e
CordicAtan9		dc.l	$003ffffa,$aaab7777,$52e5356f
CordicAtan10	dc.l	$001fffff,$55555bbb,$bb72972d
CordicAtan11	dc.l	$000fffff,$eaaaaadd,$dddd4b95
CordicAtan12	dc.l	$0007ffff,$fd555556,$eeeeedca
CordicAtan13	dc.l	$0003ffff,$ffaaaaaa,$b7777775
CordicAtan14	dc.l	$0001ffff,$fff55555,$55bbbbbc
CordicAtan15	dc.l	$0000ffff,$fffeaaaa,$aaadddde
CordicAtan16	dc.l	$00007fff,$ffffd555,$55556eef
CordicAtan17	dc.l	$00003fff,$fffffaaa,$aaaaab77
CordicAtan18	dc.l	$00001fff,$ffffff55,$5555555c
CordicAtan19	dc.l	$00000fff,$ffffffea,$aaaaaaab
CordicAtan20	dc.l	$000007ff,$fffffffd,$55555555
CordicAtan21	dc.l	$000003ff,$ffffffff,$aaaaaaab
CordicAtan22	dc.l	$000001ff,$ffffffff,$f5555555
CordicAtan23	dc.l	$000000ff,$ffffffff,$feaaaaab
CordicAtan24	dc.l	$0000007f,$ffffffff,$ffd55555
CordicAtan25	dc.l	$0000003f,$ffffffff,$fffaaaab
CordicAtan26	dc.l	$0000001f,$ffffffff,$ffff5555
CordicAtan27	dc.l	$0000000f,$ffffffff,$ffffeaab
CordicAtan28	dc.l	$00000007,$ffffffff,$fffffd55
CordicAtan29	dc.l	$00000003,$ffffffff,$ffffffab
CordicAtan30	dc.l	$00000001,$ffffffff,$fffffff5
CordicAtan31	dc.l	$00000000,$ffffffff,$ffffffff
CordicAtan32	dc.l	$00000000,$80000000,$00000000
CordicAtan33	dc.l	$00000000,$40000000,$00000000
CordicAtan34	dc.l	$00000000,$20000000,$00000000
CordicAtan35	dc.l	$00000000,$10000000,$00000000
CordicAtan36	dc.l	$00000000,$08000000,$00000000
CordicAtan37	dc.l	$00000000,$04000000,$00000000
CordicAtan38	dc.l	$00000000,$02000000,$00000000
CordicAtan39	dc.l	$00000000,$01000000,$00000000
CordicAtan40	dc.l	$00000000,$00800000,$00000000
CordicAtan41	dc.l	$00000000,$00400000,$00000000
CordicAtan42	dc.l	$00000000,$00200000,$00000000
CordicAtan43	dc.l	$00000000,$00100000,$00000000
CordicAtan44	dc.l	$00000000,$00080000,$00000000
CordicAtan45	dc.l	$00000000,$00040000,$00000000
CordicAtan46	dc.l	$00000000,$00020000,$00000000
CordicAtan47	dc.l	$00000000,$00010000,$00000000
CordicAtan48	dc.l	$00000000,$00008000,$00000000
CordicAtan49	dc.l	$00000000,$00004000,$00000000
CordicAtan50	dc.l	$00000000,$00002000,$00000000
CordicAtan51	dc.l	$00000000,$00001000,$00000000
CordicAtan52	dc.l	$00000000,$00000800,$00000000
CordicAtan53	dc.l	$00000000,$00000400,$00000000
CordicAtan54	dc.l	$00000000,$00000200,$00000000
CordicAtan55	dc.l	$00000000,$00000100,$00000000
CordicAtan56	dc.l	$00000000,$00000080,$00000000
CordicAtan57	dc.l	$00000000,$00000040,$00000000
CordicAtan58	dc.l	$00000000,$00000020,$00000000
CordicAtan59	dc.l	$00000000,$00000010,$00000000
CordicAtan60	dc.l	$00000000,$00000008,$00000000
CordicAtan61	dc.l	$00000000,$00000004,$00000000
