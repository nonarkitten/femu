;
;
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