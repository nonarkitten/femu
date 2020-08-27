;
; Moves the contents of the specified control register (Rc)
; to the specified general register (Rn) - like movec
; instruction but supports 080 specific control registers.
;
; INPUTS
;	\1 -- Control register number in hex.
;
; RESULT
;	\2 -- General register number in hex.
;
MOVEFROMC macro
    dc.w        $4e7a,$\2\1
endm


;
; Moves the contents of the specified general register (Rn)
; to the specified control register (Rc) - like movec
; instruction but supports 080 specific control registers.
;
; INPUTS
;	\1 -- General register number in hex.
;
; RESULT
;	\2 -- Control register number in hex.
;
MOVETOC macro
    dc.w        $4e7b,$\1\2
endm


;
; Opens specified library. If library cannot be opened 
; optionally prints error message to the output.
;
; INPUTS
;	\1 -- Library name.
;	\2 -- Minimum library version.
;	\3 -- Library pointer.
;	\4 -- Error handler.
;	\5 -- Error message (optional).
;
; RESULT
;	\3 -- Library pointer.
;
OPENLIB macro
	movea.l		_AbsExecBase,a6
	lea.l		\1,a1 
	move.l		#\2,d0 
	jsr			_LVOOpenLibrary(a6)
    move.l		d0,\3
	tst.l		d0	
	bne.s		.\@Ok
	ifnb	\5
		WRITEOUT	#\5
	endif
	bra.w		\4
	.\@Ok:
endm


;
; Closes specified library if it is open. Does nothing 
; if it is not open (library pointer is 0).
;
; INPUTS
;	\1 -- Library pointer.
;
CLOSELIB macro
	tst.l		\1
	beq.s		.\@Ok
	movea.l		_AbsExecBase,a6
	movea.l		\1,a1
	jsr			_LVOCloseLibrary(a6)
	.\@Ok:
endm
	

;
; Tests given conditional predicate against fpsr 
; and calls corresponding handler handler.
;
; INPUTS
;	d0 -- Conditional predicate.
;	\1 -- True handler.
;	\2 -- False handler.
;
TESTCONDITION macro
	
	; Get truth table entry for fpsr condition code
	ifd FPSR080
		fmove.l		fpsr,d1
		rol.l		#8,d1
		and.w		#$0f,d1
	else
		bfextu		RegFpsrCc{0:8},d1
	endc
	move.l		(FPSRCCTRUTH,d1.w*4),d1
	
	; Test truth bit for the predicate
	btst		d0,d1
	bne.w		\1
	bra.w		\2

endm


;
; Moves value from floating point register to data register.
;
; INPUTS
;	\1 -- Index register.
;
; RESULT
;	\2 -- Data register.
;	\3 -- Data register.
;
MOVEFPNTODN macro
	ifd FPN080
		addi.b		#32,\1
		storei		\1,\3
		vperm		#$01230123,\3,\3,\2
		subi.b		#32,\1
	else
		lea.l		RegFpn,a1
		movem.l		(a1,\1.w*8),\2/\3
	endif
endm


;
; Moves value from data register to floating point register.
; 
; INPUTS
;	\1 -- Index register.
;
; RESULT
;	\2 -- Data register.
;	\3 -- Data register.
;
MOVEDNTOFPN macro
	ifd FPN080
		addi.b		#32,\1
		vperm		#$4567cdef,\2,\3,e8
		loadi		e8,\1
		subi.b		#32,\1
	else
		lea.l		RegFpn,a1
		movem.l		\2/\3,(a1,\1.w*8)
	endif
endm


;
; Moves value from floating point register to memory.
;
; INPUTS
;	\1 -- Index register.
;
; RESULT
;	\2 -- Address register.
;
MOVEFPNTOEA macro
	ifd FPN080
		addi.b		#32,\1
		storei		\1,(\2)
		subi.b		#32,\1
	else
		lea.l		RegFpn,a0
		move.l		(a0,\1.w*8),(\2)
		move.l		($04,a0,\1.w*8),$04(\2)
	endif
endm


;
; Moves value from memory to floating point register.
; 
; INPUTS
;	\2 -- Address register.
;
; RESULT
;	\1 -- Index register.
;
MOVEEATOFPN macro
	ifd FPN080
		addi.b		#32,\1
		loadi		(\2),\1
		subi.b		#32,\1
	else
		lea.l		RegFpn,a0
		move.l		(\2),(a0,\1.w*8)
		move.l		$04(\2),($04,a0,\1.w*8)
	endif
endm


;
; Shifts stack and stack frame to left. Please notice
; that this macro is highly inefficient since it moves
; memory byte by byte and has some stupid other things.
; 
; INPUTS
;	\1 -- Data length.
;	STACKFRAME -- Stack frame address.
;
; RESULT
;	a0 -- Effective address.
;
STACKSL macro 

	; Calculate region to shift
	movea.l		sp,a0
	movea.l		STACKFRAME,a1
	adda.l		#STACKLENGTH,a1
	
	; Shift region 
	neg.l		\1
	.\@Loop:
	move.b		(a0),(a0,\1.l)
	adda.l		#1,a0
	cmpa.l		a0,a1
	bgt.s		.\@Loop
	neg.l		\1
	
	; Update pointers
	suba.l		\1,sp
	suba.l		\1,STACKFRAME
	suba.l		\1,a0
	
endm

;
; Shifts stack and stack frame to right. Please notice
; that this macro is highly inefficient since it moves
; memory byte by byte and has some stupid other things.
; 
; INPUTS
;	\1 -- Data length.
;	STACKFRAME -- Stack frame address.
;
; RESULT
;	a0 -- Effective address.
;
STACKSR macro 

	; Calculate region to backup
	movea.l		STACKFRAME,a0
	adda.l		#STACKLENGTH,a0
	move.l		a0,a1
	adda.l		\1,a1
	lea.l		TempEa,a2

	; Backup region 
	.\@Backup:
	move.b		(a0),(a2)
	adda.l		#1,a0
	adda.l		#1,a2
	cmpa.l		a0,a1
	bgt.s		.\@Backup
	
	; Calculate region to shift
	movea.l		STACKFRAME,a1
	adda.l		#STACKLENGTH,a1
	
	; Shift region
	.\@Loop:
	suba.l		#1,a1
	move.b		(a1),(a1,\1.l)
	cmpa.l		sp,a1
	bgt.s		.\@Loop
	
	; Update pointers
	adda.l		\1,sp
	adda.l		\1,STACKFRAME
	lea.l		TempEa,a0
	
endm


;
; Increments FAULTPC by given amount.
; 
; INPUTS
;	\1 -- Amount.
;
INREMENTPC macro 
	add.l		\1,FAULTPC
endm


;
; Reverses a byte.
; 
; INPUTS
;	\1 -- Byte.
; 
; RESULT
;	\1 -- Reversed byte.
;
REVERSEBYTE macro
    bfclr       \1{0:24}
    move.b      (REVERSEDBYTES,\1.w),\1
endm
REVERSEDBYTES
    dc.b      $00,$80,$40,$c0,$20,$a0,$60,$e0,$10,$90,$50,$d0,$30,$b0,$70,$f0
    dc.b      $08,$88,$48,$c8,$28,$a8,$68,$e8,$18,$98,$58,$d8,$38,$b8,$78,$f8
    dc.b      $04,$84,$44,$c4,$24,$a4,$64,$e4,$14,$94,$54,$d4,$34,$b4,$74,$f4
    dc.b      $0c,$8c,$4c,$cc,$2c,$ac,$6c,$ec,$1c,$9c,$5c,$dc,$3c,$bc,$7c,$fc
    dc.b      $02,$82,$42,$c2,$22,$a2,$62,$e2,$12,$92,$52,$d2,$32,$b2,$72,$f2
    dc.b      $0a,$8a,$4a,$ca,$2a,$aa,$6a,$ea,$1a,$9a,$5a,$da,$3a,$ba,$7a,$fa
    dc.b      $06,$86,$46,$c6,$26,$a6,$66,$e6,$16,$96,$56,$d6,$36,$b6,$76,$f6
    dc.b      $0e,$8e,$4e,$ce,$2e,$ae,$6e,$ee,$1e,$9e,$5e,$de,$3e,$be,$7e,$fe
    dc.b      $01,$81,$41,$c1,$21,$a1,$61,$e1,$11,$91,$51,$d1,$31,$b1,$71,$f1
    dc.b      $09,$89,$49,$c9,$29,$a9,$69,$e9,$19,$99,$59,$d9,$39,$b9,$79,$f9
    dc.b      $05,$85,$45,$c5,$25,$a5,$65,$e5,$15,$95,$55,$d5,$35,$b5,$75,$f5
    dc.b      $0d,$8d,$4d,$cd,$2d,$ad,$6d,$ed,$1d,$9d,$5d,$dd,$3d,$bd,$7d,$fd
    dc.b      $03,$83,$43,$c3,$23,$a3,$63,$e3,$13,$93,$53,$d3,$33,$b3,$73,$f3
    dc.b      $0b,$8b,$4b,$cb,$2b,$ab,$6b,$eb,$1b,$9b,$5b,$db,$3b,$bb,$7b,$fb
    dc.b      $07,$87,$47,$c7,$27,$a7,$67,$e7,$17,$97,$57,$d7,$37,$b7,$77,$f7
    dc.b      $0f,$8f,$4f,$cf,$2f,$af,$6f,$ef,$1f,$9f,$5f,$df,$3f,$bf,$7f,$ff


;
; Sets FPSR condition code based on double value. 
; Function will modify values and will not restore 
; them so be aware (call this as last step). 
; 
; INPUTS
;	\1 -- Double.
;   \2 -- Double.
; 
SETCC macro

	; Clear all flags
	moveq		#0,d6

	; Clear sign and set N flag
	bclr.l		#31,\1
	beq.s		.NoN
	ori.b		#CCN,d6
	.NoN:
	
	; Check and set Z flag
	tst.l		\1
	bne.s		.NoZ
	tst.l		\2
	bne.s		.NoZ
	ori.b		#CCZ,d6
	bra.s		.FlagsOk
	.NoZ:
	
	; Check NaN and I flags
	cmp.l		#$7ff00000,\1
	bmi.s		.FlagsOk
	
	; Check and set I flag
	bne.s		.IsNan
	tst.l		\2
	bne.s		.IsNan
	ori.b		#CCI,d6
	bra.s		.FlagsOk
	
	; Check and set NaN flag
	.IsNan:
	ori.b		#CCNAN,d6
	
	; Done
	.FlagsOk:
	ifd	FPSR080
		ori.b		#$80,d6	; set/restore "FPU IN USE" flag
		roxr.l		#8,d6
		fmove.l		d6,fpsr
	else
		move.b		d6,RegFpsrCc
	endif
endm


;
; Get FPCR into data register \1 (always .l).
; 
; RESULT
;	\1 -- FPCR value.
;
GETFPCR macro
	ifnd FPC080
		move.l		RegFpcrReserved,\1
	else
		fmove.l		FPCR,\1
	endc
endm

;
; Store data register \1 in FPCR (.l).
; 
; INPUTS
;	\1 -- FPCR value.
;
SETFPCR macro
	ifnd FPC080
		move.l		\1,RegFpcrReserved
	else
		fmove.l		\1,FPCR
	endc
endm
