;
; Checklist #7 ("trim the trap prologue/epilogue"): investigated, not
; implemented -- the full d0-d7/a0-sp save below can't be safely narrowed
; per-handler under the current addressing scheme. ea.asm's GETEAVALUE/
; GetEa/ADDAN reach any of the 15 general registers by a *runtime*-computed
; offset -- (OSTACKAN,STACKFRAME,dN.w), OSTACKAN/OSTACKDN fixed at -32/-64
; from STACKFRAME below -- into exactly the frame this movem lays down, so
; any FPU opcode with a memory operand can name any a0-a6/d0-d7 in its EA;
; the save side can't be narrowed below the full set without already having
; decoded the instruction that determines which register that is.
;
; A narrower, real case does exist -- fadd/fsub/fmul/fdiv/fcmp/fabs/fneg/
; ftst/fscale/fgetexp/fgetman (and their fs*/fd* precision-forced siblings,
; same handler code) never touch a0/a2/a3/a6 in any of their own code or in
; MOVEFPNTODN/MOVEDNTOFPN/SETCC/the FE_* math macros (audited by grep across
; every src/ops/*.asm; all stay within d0-d6/a1) -- but only when the
; instruction's source-specifier bit (bit 14) says "FPm register", not
; memory; the same handler reached via the EA-to-reg path needs GetEa (a0)
; and the full OSTACKAN image regardless of which op it is. It doesn't pay
; for itself: movem.l -(sp) only reserves space for registers actually in
; its list, so dropping a0/a2/a3/a6 from the transfer also shrinks the
; frame -- but OSTACKAN/OSTACKDN index every register's slot by its fixed
; 68K register number (STACKFRAME + OSTACKAN + regnum*4), so those four
; slots still have to exist at their normal offsets for any later-in-the-
; chain instruction (checklist #6) that does need them, or for
; POSTHANDLEEXCEPTION's unconditional restore. Gap-filling the skipped
; slots (e.g. subq.l #4,sp per register) to keep the fixed offsets intact
; costs about what the move.l aN,-(sp) it replaces did -- the saving
; evaporates once the frame's fixed-offset addressing is preserved, which
; it must be for correctness. Real per-handler trimming needs that
; addressing scheme itself to change (a fast EA path that doesn't need the
; general OSTACKAN lookup for its own fixed-shape frame) -- that's #8's
; territory, not this row's. See README.md's #7 row for the full writeup.
;
PREHANDLEEXCEPTION macro

	; Disable interrupts
	ori.w		#%0000011100000000,sr
	
	btst.b		#5,(sp)
	beq.s		.\@User
	.\@Super:
	
		; Save registers
		movem.l			d0-d7/a0-sp,-(sp) ; TODO: does predecrement happend BEFORE sp is stored??? perhaps that's why rot3d is borked?
		
		; Analyze stack frame 
		move.l			sp,STACKFRAME
		adda.l			#64,STACKFRAME
		ifd STACK020
			addi.l			#STACKLENGTH,(OSTACKSP,STACKFRAME)
			move.l			$02(STACKFRAME),FAULTPC
		endif
		ifd STACK040 
			addi.l			#STACKLENGTH,(OSTACKSP,STACKFRAME)
			move.l			$0c(STACKFRAME),FAULTPC
		endif
		ifd STACK080
			addi.l			#STACKLENGTH,(OSTACKSP,STACKFRAME)
			MOVEFROMC       00f,c
		endif
		move.l			(FAULTPC),INSTRUCTION
		
		bra.s		.\@Ok
	.\@User:

		; Save registers
		movem.l			d0-d7/a0-sp,-(sp)
		move.l			usp,a0
		move.l			a0,60(sp) 
	
		; Analyze stack frame 
		move.l			sp,STACKFRAME
		adda.l			#64,STACKFRAME
		ifd STACK020
			move.l			$02(STACKFRAME),FAULTPC
		endif
		ifd STACK040 
			move.l			$0c(STACKFRAME),FAULTPC
		endif
		ifd STACK080
			MOVEFROMC       00f,c
		endif
		move.l			(FAULTPC),INSTRUCTION
		
	.\@Ok:

	; Debug instruction
	;WRITEDEBUG	#DEBUGINSTRUCTION,INSTRUCTION
	
endm


;
;
;
POSTHANDLEEXCEPTION macro
	btst.b		#5,(STACKFRAME)
	beq.s		.\@User
	
	.\@Super:
		
		; Update stack frame
		ifd STACK020
			move.l			FAULTPC,$02(STACKFRAME)
			subi.l			#STACKLENGTH,(OSTACKSP,STACKFRAME)
		endif
		ifd STACK040
			subi.l			#STACKLENGTH,(OSTACKSP,STACKFRAME)
		endif
		ifd STACK080
			subi.l			#STACKLENGTH,(OSTACKSP,STACKFRAME)
		endif

		; Restore registers
		adda.l			#64,sp
		movem.l			OSTACKDN(STACKFRAME),d0-d7/a0-a6		
		bra.s		.\@Ok
	.\@User:
	
		; Update stack frame
		ifd STACK020
			move.l		FAULTPC,$02(STACKFRAME)
		endif

		; Restore registers
		adda.l			#64,sp
		movea.l			OSTACKSP(STACKFRAME),a0
		move.l			a0,usp
		movem.l			OSTACKDN(STACKFRAME),d0-d7/a0-a6
	.\@Ok:
	
	; Return from the exception
	rte
	
endm


;
; Exception handler.
;
; Checklist #6: opcode chaining. Every handler already advances FAULTPC
; past its own opcode/extension/EA words (see e.g. FaddHandler's
; INREMENTPC) before rts-ing back here, so once EmulateInstruction
; returns, (FAULTPC) is exactly the next instruction the CPU would fetch
; after our eventual rte. If that next word also looks like an F-line
; (coprocessor) opcode -- the same test the CPU itself would have used to
; decide whether to trap here again -- decode and run it directly instead
; of paying rte + a fresh trap entry for it. Falls through to the normal
; POSTHANDLEEXCEPTION/rte the first time the next instruction isn't one of
; ours, so a non-FPU instruction (or the end of a run of them) is handled
; exactly as before.
;
HandleException
	PREHANDLEEXCEPTION
	.ChainLoop:
	jsr EmulateInstruction

	; Peek the next instruction (opcode word + one extension word, same
	; two-word fetch PREHANDLEEXCEPTION did for the first one) and check
	; its top nibble for the F-line pattern.
	move.l		(FAULTPC),INSTRUCTION
	bfextu		INSTRUCTION{0:4},d0
	cmp.b		#$f,d0
	beq.s		.ChainLoop

	POSTHANDLEEXCEPTION


;
; Generic unsupported feature function. Will print error message, dump some
; memory for futher analysis and then halt.
;
; INPUTS
;	a0 -- Address to error message.
;
Unsupported

	; Output error message
	movea.l		$02(STACKFRAME),a1
	movea.l		$0c(STACKFRAME),a2
	WRITEOUT	#MSGUNSUPPORTED,a0,(STACKFRAME),$04(STACKFRAME),$08(STACKFRAME),$0c(STACKFRAME),(a1),(a2)

	; Trigger debugger
	clr.w		$100

	; Halt
	stop		#$2700