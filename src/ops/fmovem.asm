;
; Checklist #11: fmovem's real 68881/68882 register-list order has a
; well-known gotcha, confirmed against Musashi's own m68kfpu.c
; (bench/vendor/musashi/m68kfpu.c, fmovem()/WRITE_EA_FPE()/READ_EA_FPE()
; -- a real, independent reference implementation already vendored in
; this repo) and cross-checked against the Motorola manual's own
; description of plain MOVEM's predecrement mask convention, which
; FMOVEM's extension-word "mode" bit (bit 12) follows exactly:
;
;   - Predecrement (-(An)): register-list bit N selects FPn directly
;     (bit0=FP0 ... bit7=FP7) -- no reversal.
;   - Postincrement/control (every other addressing mode -- (An),
;     (An)+, (d16,An), absolute, ...): register-list bit N selects
;     FP(7-N) instead (bit0=FP7 ... bit7=FP0) -- reversed.
;
; GETFMOVEMREGS below already gets this half right: it tests bit 12
; and reverses the raw byte (REVERSEBYTE) exactly when it's set, which
; correctly NORMALIZES either encoding back to one canonical "bit N =
; FPn" convention before the per-register move macros run.
;
; What was actually wrong is downstream of that: once normalized, the
; CORRECT memory layout is still not "ascending address = ascending FP
; number" -- it's the opposite. Walking either real addressing mode
; register-by-register (Musashi's WRITE_EA_FPE/READ_EA_FPE do this
; explicitly, one register at a time) shows that the FIRST register
; processed always lands at the address CLOSEST to the list's edge
; nearest the un-adjusted address register, and later-processed
; (higher-numbered, post-normalization) registers end up progressively
; further from it -- which works out, for both predecrement and
; postincrement/control alike, to: ascending memory address holds
; DESCENDING FPn. The old code called the per-register move macros in
; ascending order (FP0 first, at the lowest address) -- backwards.
; Verified by hand-tracing both Musashi's loop and this file's own
; macros against the same register list before touching anything.
;
; Fixed by reversing the literal call order of FMOVEMEAFPN/FMOVEMFPNEA
; below (FP7 first, FP0 last) -- GETFMOVEMREGS's own normalization
; logic needed no change at all. The pre-existing fmove_probe.asm
; fmovem vectors encoded the SAME wrong assumption this code had (both
; written by the same original, unfixed understanding), so they
; "passed" without ever exercising the real bug; bench/src/harness.c's
; expected values are corrected alongside this fix, and two new
; vectors (predecrement store, postincrement load) were added since
; the old vectors only used plain "(a0)" and never exercised
; GETFMOVEMREGS's reversal path at all.
;


;
;
;
GETFMOVELENGTH macro
	bfextu		INSTRUCTION{24:8},\1
	move.b		(FMOVEMLENGTHS,d0.w),\1
endm


;
;
;
GETFMOVEMREGS macro
	btst		#11,INSTRUCTION
	beq.s		.\@Static
    
    .\@Dynamic:
	lea.l		ERRUNSUPPORTEDREGLIST,a0
	jmp			Unsupported
    
	.\@Reverse:
	REVERSEBYTE \1
	bra.s       .\@GotIt
    
	.\@Static:
	move.b		INSTRUCTION,\1
	btst		#12,INSTRUCTION
	bne.s		.\@Reverse
    
    .\@GotIt:
endm


;
; fmovem's memory format is always 96-bit extended (FMOVEMLENGTHS below
; is all multiples of 12) -- byte-identical to the internal format now
; (checklist #4), so this is a straight movem.l with no per-register
; ExtendedToDouble/DoubleToExtended jsr at all anymore. This is the one
; place #4's design pass found an unambiguous win: the old version paid
; that conversion once per register in the list.
;
FMOVEMEAFPN macro
	btst.l			#\1,\2
	beq.s			.\@NoMove
    movem.l			(a3),d0/d1/d2
    move.l          #\1,d5
	MOVEDNTOFPN     d5,d0,d1,d2
    adda.l			#$0c,a3
    .\@NoMove:
endm


;
;
;
FMOVEMFPNEA macro
	btst.l			#\1,\2
	beq.s			.\@NoMove
    move.l          #\1,d5
	MOVEFPNTODN		d5,d0,d1,d2
    movem.l			d0/d1/d2,(a3)
	adda.l			#$0c,a3
    .\@NoMove:
endm


;
; fmovem ea to register emulation
;
FmovemEaRegHandler
	WRITEDEBUG		#.DEBUGOP,INSTRUCTION
	INREMENTPC		#$04
	GETFMOVELENGTH  d0
	GETEA			a3
	GETFMOVEMREGS   d4
	FMOVEMEAFPN		7,d4
	FMOVEMEAFPN		6,d4
	FMOVEMEAFPN		5,d4
	FMOVEMEAFPN		4,d4
	FMOVEMEAFPN		3,d4
	FMOVEMEAFPN		2,d4
	FMOVEMEAFPN		1,d4
	FMOVEMEAFPN		0,d4
	rts
	.DEBUGOP:
	dc.b 			"fmovem ea,reg %08lx",10,0
	even

	
;
; fmovem register to ea emulation
;
FmovemRegEaHandler
	WRITEDEBUG		#.DEBUGOP,INSTRUCTION
	INREMENTPC	    #$04
	GETFMOVELENGTH  d0
	GETEA		    a3
	GETFMOVEMREGS   d4
	FMOVEMFPNEA	    7,d4
	FMOVEMFPNEA	    6,d4
	FMOVEMFPNEA	    5,d4
	FMOVEMFPNEA	    4,d4
	FMOVEMFPNEA	    3,d4
	FMOVEMFPNEA	    2,d4
	FMOVEMFPNEA	    1,d4
	FMOVEMFPNEA	    0,d4
	rts
	.DEBUGOP:
	dc.b 			"fmovem reg,ea %08lx",10,0
	even

;
;
;	
FMOVEMLENGTHS
	dc.b	00,12,12,24,12,24,24,36,12,24,24,36,24,36,36,48
    dc.b	12,24,24,36,24,36,36,48,24,36,36,48,36,48,48,60
	dc.b	12,24,24,36,24,36,36,48,24,36,36,48,36,48,48,60
    dc.b	24,36,36,48,36,48,48,60,36,48,48,60,48,60,60,72
	dc.b	12,24,24,36,24,36,36,48,24,36,36,48,36,48,48,60
    dc.b	24,36,36,48,36,48,48,60,36,48,48,60,48,60,60,72
	dc.b	24,36,36,48,36,48,48,60,36,48,48,60,48,60,60,72
    dc.b	36,48,48,60,48,60,60,72,48,60,60,72,60,72,72,84
	dc.b	12,24,24,36,24,36,36,48,24,36,36,48,36,48,48,60
    dc.b	24,36,36,48,36,48,48,60,36,48,48,60,48,60,60,72
	dc.b	24,36,36,48,36,48,48,60,36,48,48,60,48,60,60,72
    dc.b	36,48,48,60,48,60,60,72,48,60,60,72,60,72,72,84
	dc.b	24,36,36,48,36,48,48,60,36,48,48,60,48,60,60,72
    dc.b	36,48,48,60,48,60,60,72,48,60,60,72,60,72,72,84
	dc.b	36,48,48,60,48,60,60,72,48,60,60,72,60,72,72,84
    dc.b	48,60,60,72,60,72,72,84,60,72,72,84,72,84,84,96	