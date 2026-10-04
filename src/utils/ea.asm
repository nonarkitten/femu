;
; Gets value of the ea of the instruction in internal (native extended)
; format -- checklist #4's "enter the FPU" boundary.
;
; INPUTS
;	d0 -- Data length in bytes.
;	INSTRUCTION -- The instruction.
;
; RESULT
;	\1 -- Sign(1):exponent(15):reserved(16).
;	\2 -- Mantissa bits 63-32 (explicit integer bit at bit 31).
;	\3 -- Mantissa bits 31-0.
;
GETEAVALUE macro
	jsr				GetEaValue
	ifnc \1,d0
		move.l			d0,\1
	endif
	ifnc \2,d1
		move.l			d1,\2
	endif
	ifnc \3,d2
		move.l			d2,\3
	endif
endm


;
; Gets ea of the instruction. 
;
; INPUTS
;	d0 -- Data length in bytes.
;	INSTRUCTION -- The instruction.
;
; RESULT
;	\1 -- The ea of the instruction.
;
GETEA macro
	jsr					GetEa
	ifnc \1,a0 
		move.l			a0,\1
	endif
endm


;
; Gets number of the ea register. 
;
; INPUTS
;	INSTRUCTION -- The instruction.
;
; RESULT
;	\1 -- Register number.
;
; TODO: get rid of left shift
;
GETEAREGISTER macro
	bfextu			INSTRUCTION{13:3},\1
	lsl.b			#2,\1
endm


;
; Sets address register value to the ea.
;
; INPUTS
;	d1 -- Extension word.
;	a0 -- Ea.
;	FAULTPC -- Program counter.
;	\1 -- If set, brief extension word expected instead of full.
;
; RESULT
;	a0 -- Displaced ea.
;
ADDAN macro

	; Skip address register if suppress flag
	ifb \1
		move.l				#0,a0
		btst				#7,d1
		bne.s				.AnOk
	endif
	
	; Add address register value
	GETEAREGISTER		d0
	move.l				(OSTACKAN,STACKFRAME,d0.w),a0
	
	; Address register value added
	.AnOk:

endm


;
; Adds base displacement to the ea.
;
; INPUTS
;	d1 -- Extension word.
;	a0 -- Ea.
;	FAULTPC -- Program counter.
;
; RESULT
;	a0 -- Displaced ea.
;
ADDBD macro

	; Check base displacement type
	btst				#5,d1
	beq.s				.BdOk
	btst				#4,d1
	beq.s				.BdWord
	
	; Long base displacement
	.BdLong:
	add.l				(FAULTPC),a0
	INREMENTPC			#$04
	bra.s				.BdOk
	
	; Word base displacement
	.BdWord:
	move.w				(FAULTPC),d0
	ext.l				d0
	add.l				d0,a0
	INREMENTPC			#$02
	
	; Base displacement added
	.BdOk:
	
endm


;
; Adds index register displacement to the ea.
;
; INPUTS
;	d1 -- Extension word.
;	a0 -- Ea.
;	\1 -- If set, brief extension word expected instead of full.
;
; RESULT
;	a0 -- Displaced ea.
;
ADDXN macro

	; Skip index register if suppress flag is on
	ifb \1
		btst			#6,d1
		bne.s			.XnOk
	endif
	
	; Get index register value
	bfextu				d1{17:3},d0
	btst				#15,d1
	beq.s				.XdDn
	.XdAn:
	move.l				(OSTACKAN,STACKFRAME,d0.w*4),d0
	bra.s				.XdOk
	.XdDn:
	move.l				(OSTACKDN,STACKFRAME,d0.w*4),d0
	.XdOk:
	
	; Sign extend index register value
	btst				#11,d1
	bne.s				.XnLong
	ext.l				d0
	.XnLong:
	
	; Scale index register value
	move.l				d1,a1
	bfextu				d1{21:2},d1
	lsl.l				d1,d0
	move.l				a1,d1
	
	; Add index register displacement
	adda.l				d0,a0
	
	; Index register added
	.XnOk:
	
endm

;
; Adds word outer displacement to the ea.
;
; INPUTS
;	a0 -- Ea.
;	FAULTPC -- Program counter.
;
; RESULT
;	a0 -- Displaced ea.
;
ADDODWORD macro
	move.w				(FAULTPC),d0
	ext.l				d0
	add.l				d0,a0
	INREMENTPC			#2
endm


;
; Adds long outer displacement to the ea.
;
; INPUTS
;	a0 -- Ea.
;	FAULTPC -- Program counter.
;
; RESULT
;	a0 -- Displaced ea.
;
ADDODLONG macro
	add.l				(FAULTPC),a0
	INREMENTPC			#4
endm



;
; Gets contents of the ea of the instruction as a double.
;
; INPUTS
;	d0 -- Data length in bytes.
;	INSTRUCTION -- The instruction.
;
; RESULT
;	d0 -- Highest 32 bits of the double.
;	d1 -- Lowest 32 bits of the double.
;
; TODO: do not require data length, get it in GetEa
;
GetEaValue

	; Register to register: already the internal format, straight copy
	; -- no conversion needed at all (checklist #4's "already free"
	; register-to-register case). d3 holds the index rather than d2,
	; purely to avoid a same-register index/output dual role; the
	; index's value is fully consumed by MOVEFPNTODN's address
	; computation before it writes its result registers regardless.
	btst.l			#14,INSTRUCTION
	bne.s			.NoRegReg
	bfextu			INSTRUCTION{19:3},d3
	MOVEFPNTODN		d3,d0,d1,d2
	rts
	.NoRegReg:

	; EA-decode fast path (checklist #8): Dn, (An), (An)+, -(An) and
	; (d16,An) -- the modes real FPU code overwhelmingly uses --
	; computed directly here instead of through a nested jsr GetEa.
	; Every GETEAVALUE caller funnels through this one spot for a
	; memory operand, so resolving a0 once here (rather than once per
	; data-length handler below, each of which used to do its own
	; jsr GetEa) removes a whole subroutine call -- entry/exit overhead
	; plus GetEa's own redundant re-check of the register-to-register
	; bit this routine already ruled out above -- for the common case.
	; d0 is still this routine's own "data length in bytes" input,
	; untouched since entry, exactly what EaDnDirect/EaAnIndirectPostinc/
	; EaAnIndirectPredec's bodies below need (copied from their GetEa
	; originals, not shared with them -- a second caller showed up, so
	; per CLAUDE.md this earns the copy rather than a shared indirection).
	;
	; Dispatches on the 3-bit MODE field alone via a small jump table,
	; deliberately NOT a linear cmp/bcc chain over the modes -- an
	; earlier version of this tried that and, measured against the old
	; jsr GetEa path, came out *slower* for (An)+/-(An)/(d16,An): each
	; sits further down the chain than (An), so it paid for every
	; earlier mode's comparison on top of its own, outweighing the
	; call it avoided. A jump table costs the same two instructions
	; (bfextu+jmp) to reach ANY mode, matching GetEa's own dispatch
	; shape, so the only thing this removes is the call/return pair and
	; the redundant bit-14 recheck -- a real, uniform win, not a
	; swap of one overhead for a worse one. See README.md's #8 row for
	; both measurements.
	;
	; (An)+/-(An) with register 7 (sp) fall through to the slow path:
	; GetEa's EaAnIndirectPostincSp/PredecSp need the heavier STACKSR/
	; STACKSL stack-shift loops for the user-mode case, not worth
	; duplicating here for what's already a rare addressing choice for
	; an FP operand. Mode 001 (An direct, unsupported for an FP operand)
	; and modes 110/111 (indexed, memory-indirect, absolute, PC-
	; relative, immediate) fall through unchanged to the general GetEa.
	bfextu			INSTRUCTION{10:3},d1
	jmp				(EaFastModeVectors,d1.w*4)

	EaFastModeVectors:
	bra.w			.FastDn				; 000 Dn
	bra.w			.Slow				; 001 An direct (unsupported)
	bra.w			.FastAn				; 010 (An)
	bra.w			.FastPostinc		; 011 (An)+
	bra.w			.FastPredec			; 100 -(An)
	bra.w			.FastDisplace		; 101 (d16,An)
	bra.w			.Slow				; 110 (An) with index
	bra.w			.Slow				; 111 other modes

	.FastDn:
	GETEAREGISTER	d1
	move.l			STACKFRAME,a0
	suba.l			#64,a0
	adda.l			d1,a0
	cmp.b			#1,d0
	bne.s			.FastDnNoByte
	adda.l			#3,a0
	bra.w			.EaDone
	.FastDnNoByte:
	cmp.b			#2,d0
	bne.w			.EaDone
	adda.l			#2,a0
	bra.w			.EaDone

	.FastAn:
	GETEAREGISTER	d1
	move.l			(OSTACKAN,STACKFRAME,d1.w),a0
	bra.w			.EaDone

	.FastPostinc:
	bfextu			INSTRUCTION{13:3},d6
	cmp.b			#7,d6
	beq.w			.Slow
	move.b			d6,d1
	lsl.b			#2,d1
	move.l			(OSTACKAN,STACKFRAME,d1.w),a0
	add.l			d0,(OSTACKAN,STACKFRAME,d1.w)
	bra.w			.EaDone

	.FastPredec:
	bfextu			INSTRUCTION{13:3},d6
	cmp.b			#7,d6
	beq.w			.Slow
	move.b			d6,d1
	lsl.b			#2,d1
	sub.l			d0,(OSTACKAN,STACKFRAME,d1.w)
	move.l			(OSTACKAN,STACKFRAME,d1.w),a0
	bra.w			.EaDone

	.FastDisplace:
	GETEAREGISTER	d1
	move.l			(OSTACKAN,STACKFRAME,d1.w),a0
	move.w			(FAULTPC),d1
	ext.l			d1
	adda.l			d1,a0
	INREMENTPC		#$02
	bra.w			.EaDone

	.Slow:
	jsr				GetEa
	.EaDone:

	; Jump to data format specific getter -- a0 is already resolved by
	; the fast/slow EA computation above, so none of these call GetEa
	; themselves any more.
	bfextu			INSTRUCTION{19:3},d1
	jmp				(GetEaValueVectors,d1.w*4)

	; Byte
	GetEaValueByte:
	move.b			(a0),d0
	jsr				ByteToInternal
	rts

	; Word
	GetEaValueWord:
	move.w			(a0),d0
	jsr				WordToInternal
	rts

	; Long
	GetEaValueLong:
	move.l			(a0),d0
	jsr				LongToInternal
	rts

	; Single
	GetEaValueSingle:
	move.l			(a0),d0
	jsr				SingleToInternal
	rts

	; Double
	GetEaValueDouble:
	movem.l			(a0),d0/d1
	jsr				DoubleToInternal
	rts

	; Extended: memory layout is byte-identical to the internal format
	; (checklist #4's whole point) -- straight copy, no conversion call.
	GetEaValueExtended:
	movem.l			(a0),d0/d1/d2
	rts

	; Packed
	GetEaValuePacked:
	movem.l			(a0),d0/d1/d2
	jsr				PackedToInternal
	rts


;
; Gets ea of the instruction. 
;
; INPUTS
;	d0 -- Data length in bytes.
;	INSTRUCTION -- The instruction.
;
; RESULT
;	a0 -- The ea of the instruction.
;
; TODO: Program Counter Indirect with Index (8-Bit Displacement) Mode
; TODO: Program Counter Indirect with Index (Base Displacement) Mode
; TODO: Program Counter Memory Indirect Postindexed Mode
; TODO: Program Counter Memory Indirect Preindexed Mode
;
GetEa

	; Register to register is handled as ea to register 
	btst.l				#14,INSTRUCTION
	bne.s				.NoRegReg
	bfextu				INSTRUCTION{19:3},d1
	ifd FPN080
		lea.l				TempEa,a0
		MOVEFPNTOEA			d1,a0
	else
		; RegFpn is 12 bytes/register now (checklist #4) -- not a valid
		; scaled-index factor, so build the *12 offset as two chained
		; LEAs (index*8, then +index*4) the same way macros.asm's
		; MOVEFPNTODN etc. do, rather than clobbering d1 with a multiply.
		lea.l				RegFpn,a0
		lea.l				(a0,d1.w*8),a0
		lea.l				(a0,d1.w*4),a0
	endif
	rts
	.NoRegReg:
	
	; Jump to specific ea handler
	bfextu				INSTRUCTION{10:6},d1
	jmp					(GetEaVectors,d1.w*4)
		
	; Ea mode bits are 111, one more jump
	EeMode111:
	move.w				(FAULTPC),d1
	INREMENTPC			#$02
	btst				#8,d1
	beq.w				EaAnIndirectIndex8bit
	bfextu				d1{29:3},d0
	btst				#6,d1
	beq.s				.NoBs
	bset				#3,d0
	.NoBs:
	jmp					(EaMode111Vectors,d0.w*4)
	
	; Data register direct mode
	; TODO: this can be rewritten by using more advanced ea modes?
	EaDnDirect:
	GETEAREGISTER		d1
	move.l				STACKFRAME,a0
	suba.l				#64,a0
	adda.l				d1,a0
	cmp.b				#1,d0
	bne.s				.NoByte
	adda.l				#3,a0
	rts
	.NoByte:
	cmp.b				#2,d0
	bne.s				.NoWord
	adda.l				#2,a0
	.NoWord:
	rts
		
	; Address register indirect mode
	EaAnIndirect:
	GETEAREGISTER		d1
	move.l				(OSTACKAN,STACKFRAME,d1.w),a0
	rts
		
	; Address register indirect with postincrement mode
	EaAnIndirectPostinc:
	GETEAREGISTER		d1
	move.l				(OSTACKAN,STACKFRAME,d1.w),a0
	add.l				d0,(OSTACKAN,STACKFRAME,d1.w)
	rts
		
	; Address register (sp) indirect with postincrement mode
	EaAnIndirectPostincSp:
	move.w				(STACKFRAME),d1
	btst				#13,d1
	beq.s				EaAnIndirectPostinc
	STACKSR				d0
	rts
	
	; Address register indirect with predecrement mode
	EaAnIndirectPredec:
	GETEAREGISTER		d1
	sub.l				d0,(OSTACKAN,STACKFRAME,d1.w)
	move.l				(OSTACKAN,STACKFRAME,d1.w),a0
	rts
	
	; Address register (sp) indirect with predecrement mode
	EaAnIndirectPredecSp:
	move.w				(STACKFRAME),d1
	btst				#13,d1	
	beq.s				EaAnIndirectPredec
	STACKSL				d0
	rts
		
	; Address register indirect with displacement mode
	EaAnIndirectDisplace:
	GETEAREGISTER		d1
	move.l				(OSTACKAN,STACKFRAME,d1.w),a0
	move.w				(FAULTPC),d1
	ext.l				d1
	adda.l				d1,a0
	INREMENTPC			#$02
	rts	
		
	; Address register indirect with index (8-bit displacement) mode
	EaAnIndirectIndex8bit:
	ADDAN				brief
	move.w				d1,d0
	extb.l				d0
	adda.l				d0,a0
	ADDXN				brief
	rts		
	
	; Address register indirect with index (base displacement) mode
	EaAnIndirectIndexBase:	
	ADDAN
	ADDBD	
	ADDXN	
	rts
	
	; Memory indirect no outer displacement mode
	EaIndirectNullOd:
	ADDAN
	ADDBD	
	move.l				(a0),a0
	rts
	
	; Memory indirect word outer displacement mode
	EaIndirectWordOd:
	ADDAN
	ADDBD	
	move.l				(a0),a0
	ADDODWORD
	rts
	
	; Memory indirect long outer displacement mode
	EaIndirectLongOd:
	ADDAN
	ADDBD	
	move.l				(a0),a0
	ADDODLONG
	rts
	
	; Memory indirect preindexed no outer displacement mode
	EaIndirectPreindexNullOd:
	ADDAN
	ADDBD	
	ADDXN
	move.l				(a0),a0
	rts
	
	; Memory indirect preindexed word outer displacement mode
	EaIndirectPreindexWordOd:
	ADDAN
	ADDBD	
	ADDXN
	move.l				(a0),a0
	ADDODWORD
	rts
	
	; Memory indirect preindexed long outer displacement mode
	EaIndirectPreindexLongOd:
	ADDAN
	ADDBD	
	ADDXN
	move.l				(a0),a0
	ADDODLONG
	rts
	
	; Memory indirect postindexed no outer displacement mode
	EaIndirectPostindexNullOd:
	ADDAN
	ADDBD	
	move.l				(a0),a0
	ADDXN
	rts
	
	; Memory indirect postindexed word outer displacement mode
	EaIndirectPostindexWordOd:
	ADDAN
	ADDBD	
	move.l				(a0),a0
	ADDXN
	ADDODWORD
	rts
	
	; Memory indirect postindexed long outer displacement mode
	EaIndirectPostindexLongOd:
	ADDAN
	ADDBD	
	move.l				(a0),a0
	ADDXN
	ADDODLONG
	rts
	
	; Program counter indirect with displacement mode
	EaPcIndirectDisplace:
	move.w				(FAULTPC),d1
	ext.l				d1
	move.l				FAULTPC,a0
	add.l				d1,a0
	INREMENTPC			#$02
	rts
		
	; Absolute short addressing mode
	EaAbsoluteShort:
	move.l				(FAULTPC),d1
	swap				d1
	ext.l				d1
	movea.l				d1,a0
	INREMENTPC			#$02
	rts
	
	; Absolute long addressing mode
	EaAbsoluteLong:
	move.l				(FAULTPC),a0
	INREMENTPC			#$04 
	rts		
	
	; Immediate data
	EaImmediate:
	movea.l				FAULTPC,a0
	INREMENTPC			d0
	cmp.b				#1,d0
	bne.s				.NoByte
	adda.l				#1,a0
	INREMENTPC			#1
	.NoByte:
	rts
	
	; For 040+ ea can be found from stack frame
	ifd STACKEA
		EaStackFrame:
		move.l				$08(STACKFRAME),a0
		rts
	endif
	
	; Unsupported addressing mode
	EaUnsupported:
	lea					ERRUNSUPPORTEDEA,a0
	jmp					Unsupported

	
;
; Get ea value vectors.
;	
GetEaValueVectors:
	bra.w	GetEaValueLong				; 000 long
	bra.w	GetEaValueSingle			; 001 single
	bra.w	GetEaValueExtended			; 010 extended
	bra.w	GetEaValuePacked			; 011 packed
	bra.w	GetEaValueWord				; 100 word
	bra.w	GetEaValueDouble			; 101 double
	bra.w	GetEaValueByte				; 110 byte
	bra.w	EaUnsupported				; 111 unused
	
	
;
; Get ea vectors.
;
GetEaVectors
	ifd STACKEA
		bra.w	EaDnDirect				; 000000 d0
		bra.w	EaDnDirect				; 000001 d1
		bra.w	EaDnDirect				; 000010 d2
		bra.w	EaDnDirect				; 000011 d3
		bra.w	EaDnDirect				; 000100 d4
		bra.w	EaDnDirect				; 000101 d5
		bra.w	EaDnDirect				; 000110 d6
		bra.w	EaDnDirect				; 000111 d7
		bra.w	EaUnsupported			; 001000 unused
		bra.w	EaUnsupported			; 001001 unused
		bra.w	EaUnsupported			; 001010 unused
		bra.w	EaUnsupported			; 001011 unused
		bra.w	EaUnsupported			; 001100 unused
		bra.w	EaUnsupported			; 001101 unused
		bra.w	EaUnsupported			; 001110 unused
		bra.w	EaUnsupported			; 001111 unused
		bra.w	EaStackFrame			; 010000 (a0) 
		bra.w	EaStackFrame			; 010001 (a1)
		bra.w	EaStackFrame			; 010010 (a2)
		bra.w	EaStackFrame			; 010011 (a3)
		bra.w	EaStackFrame			; 010100 (a4)
		bra.w	EaStackFrame			; 010101 (a5)
		bra.w	EaStackFrame			; 010110 (a6)
		bra.w	EaStackFrame			; 010111 (sp)
		bra.w	EaAnIndirectPostinc		; 011000 (a0)+
		bra.w	EaAnIndirectPostinc		; 011001 (a1)+
		bra.w	EaAnIndirectPostinc		; 011010 (a2)+
		bra.w	EaAnIndirectPostinc		; 011011 (a3)+
		bra.w	EaAnIndirectPostinc		; 011100 (a4)+
		bra.w	EaAnIndirectPostinc		; 011101 (a5)+
		bra.w	EaAnIndirectPostinc		; 011110 (a6)+
		bra.w	EaAnIndirectPostincSp	; 011111 (sp)+
		bra.w	EaAnIndirectPredec		; 100000 -(a0)
		bra.w	EaAnIndirectPredec		; 100001 -(a1)
		bra.w	EaAnIndirectPredec		; 100010 -(a2)
		bra.w	EaAnIndirectPredec		; 100011 -(a3)
		bra.w	EaAnIndirectPredec		; 100100 -(a4)
		bra.w	EaAnIndirectPredec		; 100101 -(a5)
		bra.w	EaAnIndirectPredec		; 100110 -(a6)
		bra.w	EaAnIndirectPredecSp	; 100111 -(sp)
		bra.w	EaStackFrame			; 101000 (d16,a0)
		bra.w	EaStackFrame			; 101001 (d16,a1)
		bra.w	EaStackFrame			; 101010 (d16,a2)
		bra.w	EaStackFrame			; 101011 (d16,a3)
		bra.w	EaStackFrame			; 101100 (d16,a4)
		bra.w	EaStackFrame			; 101101 (d16,a5)
		bra.w	EaStackFrame			; 101110 (d16,a6)
		bra.w	EaStackFrame			; 101111 (d16,sp)
		bra.w	EaStackFrame			; 110000 (bd,a0,xn)
		bra.w	EaStackFrame			; 110001 (bd,a1,xn)
		bra.w	EaStackFrame			; 110010 (bd,a2,xn)
		bra.w	EaStackFrame			; 110011 (bd,a3,xn)
		bra.w	EaStackFrame			; 110100 (bd,a4,xn)
		bra.w	EaStackFrame			; 110101 (bd,a5,xn)
		bra.w	EaStackFrame			; 110110 (bd,a6,xn)
		bra.w	EaStackFrame			; 110111 (bd,sp,xn)
		bra.w	EaStackFrame			; 111000 (xxx).w
		bra.w	EaStackFrame			; 111001 (xxx).l
		bra.w	EaStackFrame			; 111010 (d16,pc)
		bra.w	EaStackFrame			; 111011 (d8,pc,xn)
		bra.w	EaImmediate				; 111100 #data
		bra.w	EaUnsupported			; 111101 unused
		bra.w	EaUnsupported			; 111110 unused
		bra.w	EaUnsupported			; 111111 unused
	else
		bra.w	EaDnDirect				; 000000 d0
		bra.w	EaDnDirect				; 000001 d1
		bra.w	EaDnDirect				; 000010 d2
		bra.w	EaDnDirect				; 000011 d3
		bra.w	EaDnDirect				; 000100 d4
		bra.w	EaDnDirect				; 000101 d5
		bra.w	EaDnDirect				; 000110 d6
		bra.w	EaDnDirect				; 000111 d7
		bra.w	EaUnsupported			; 001000 unused
		bra.w	EaUnsupported			; 001001 unused
		bra.w	EaUnsupported			; 001010 unused
		bra.w	EaUnsupported			; 001011 unused
		bra.w	EaUnsupported			; 001100 unused
		bra.w	EaUnsupported			; 001101 unused
		bra.w	EaUnsupported			; 001110 unused
		bra.w	EaUnsupported			; 001111 unused
		bra.w	EaAnIndirect			; 010000 (a0) 
		bra.w	EaAnIndirect			; 010001 (a1)
		bra.w	EaAnIndirect			; 010010 (a2)
		bra.w	EaAnIndirect			; 010011 (a3)
		bra.w	EaAnIndirect			; 010100 (a4)
		bra.w	EaAnIndirect			; 010101 (a5)
		bra.w	EaAnIndirect			; 010110 (a6)
		bra.w	EaAnIndirect			; 010111 (sp)
		bra.w	EaAnIndirectPostinc		; 011000 (a0)+
		bra.w	EaAnIndirectPostinc		; 011001 (a1)+
		bra.w	EaAnIndirectPostinc		; 011010 (a2)+
		bra.w	EaAnIndirectPostinc		; 011011 (a3)+
		bra.w	EaAnIndirectPostinc		; 011100 (a4)+
		bra.w	EaAnIndirectPostinc		; 011101 (a5)+
		bra.w	EaAnIndirectPostinc		; 011110 (a6)+
		bra.w	EaAnIndirectPostincSp	; 011111 (sp)+
		bra.w	EaAnIndirectPredec		; 100000 -(a0)
		bra.w	EaAnIndirectPredec		; 100001 -(a1)
		bra.w	EaAnIndirectPredec		; 100010 -(a2)
		bra.w	EaAnIndirectPredec		; 100011 -(a3)
		bra.w	EaAnIndirectPredec		; 100100 -(a4)
		bra.w	EaAnIndirectPredec		; 100101 -(a5)
		bra.w	EaAnIndirectPredec		; 100110 -(a6)
		bra.w	EaAnIndirectPredecSp	; 100111 -(sp)
		bra.w	EaAnIndirectDisplace	; 101000 (d16,a0)
		bra.w	EaAnIndirectDisplace	; 101001 (d16,a1)
		bra.w	EaAnIndirectDisplace	; 101010 (d16,a2)
		bra.w	EaAnIndirectDisplace	; 101011 (d16,a3)
		bra.w	EaAnIndirectDisplace	; 101100 (d16,a4)
		bra.w	EaAnIndirectDisplace	; 101101 (d16,a5)
		bra.w	EaAnIndirectDisplace	; 101110 (d16,a6)
		bra.w	EaAnIndirectDisplace	; 101111 (d16,sp)
		bra.w	EeMode111				; 110000 (bd,a0,xn)
		bra.w	EeMode111				; 110001 (bd,a1,xn)
		bra.w	EeMode111				; 110010 (bd,a2,xn)
		bra.w	EeMode111				; 110011 (bd,a3,xn)
		bra.w	EeMode111				; 110100 (bd,a4,xn)
		bra.w	EeMode111				; 110101 (bd,a5,xn)
		bra.w	EeMode111				; 110110 (bd,a6,xn)
		bra.w	EeMode111				; 110111 (bd,sp,xn)
		bra.w	EaAbsoluteShort			; 111000 (xxx).w
		bra.w	EaAbsoluteLong			; 111001 (xxx).l
		bra.w	EaPcIndirectDisplace	; 111010 (d16,pc)
		bra.w	EaUnsupported			; 111011 (d8,pc,xn)
		bra.w	EaImmediate				; 111100 #data
		bra.w	EaUnsupported			; 111101 unused
		bra.w	EaUnsupported			; 111110 unused
		bra.w	EaUnsupported			; 111111 unused
	endif


;
; Ea mode 111 vectors.
;
EaMode111Vectors
	bra.w	EaAnIndirectIndexBase		; 0000 No memory indirect
	bra.w	EaIndirectPreindexNullOd	; 0001 Indirect preindexed with null outer displacement
	bra.w	EaIndirectPreindexWordOd	; 0010 Indirect preindexed with word outer displacement
	bra.w	EaIndirectPreindexLongOd	; 0011 Indirect preindexed with long outer displacement
	bra.w	EaUnsupported				; 0100 Unused
	bra.w	EaIndirectPostindexNullOd	; 0101 Indirect postindexed with null outer displacement
	bra.w	EaIndirectPostindexWordOd	; 0110 Indirect postindexed with word outer displacement
	bra.w	EaIndirectPostindexLongOd	; 0111 Indirect postindexed with long outer displacement
	bra.w	EaAnIndirectIndexBase		; 1000 No memory indirect
	bra.w	EaIndirectNullOd			; 1001 Memory indirect with null outer displacement
	bra.w	EaIndirectWordOd			; 1010 Memory indirect with word outer displacement
	bra.w	EaIndirectLongOd			; 1011 Memory indirect with Long outer displacement
	bra.w	EaUnsupported				; 1100 Unused
	bra.w	EaUnsupported				; 1101 Unused
	bra.w	EaUnsupported				; 1110 Unused
	bra.w	EaUnsupported				; 1111 Unused
