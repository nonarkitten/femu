;
; fmove ea to fpcr
;
FmoveEaToFpcrHandler

	; Debug instruction
	WRITEDEBUG		#.DEBUGOP,INSTRUCTION

	; Increment PC
	INREMENTPC		#$04
	
	; Get ea - temporarily faking data format so we can use ordinary functions
	move.l			INSTRUCTION,-(sp)
	ori.w			#%0100000000000000,INSTRUCTION
	andi.w			#%1110001111111111,INSTRUCTION
	GETDATALENGTH	d0
	GETEA			a0
	move.l			(sp)+,INSTRUCTION
	
	; Move ea to fpcr
	btst			#12,INSTRUCTION
	beq.s			.NoFpcr
	lea.l			RegFpcrReserved,a1
	move.l			(a0),(a1)
	rts
	.NoFpcr:
	
	; Move ea to fpsr
	btst			#11,INSTRUCTION
	beq.s			.NoFpsr
	ifd	FPSR080
		; TODO: untested (implemented now in hw so should not be called)!
		fmove.l			(a0),fpsr
	else
		lea.l			RegFpsrCc,a1
		move.l			(a0),(a1)
	endif
	rts
	.NoFpsr:
	
	; Move ea to fpiar
	lea.l			RegFpiar,a1
	move.l			(a0),(a1)
	rts
	
	; Debug constants
	.DEBUGOP:
	dc.b 			"fmove ea,fpcr %08lx",10,0
	even
	
	
;
; fmove fpcr to ea
; 
FmoveFpcrToEaHandler

	; Debug instruction
	WRITEDEBUG		#.DEBUGOP,INSTRUCTION

	; Increment PC
	INREMENTPC		#$04
	
	; Get ea - temporarily faking data format so we can use ordinary functions
	move.l			INSTRUCTION,-(sp)
	ori.w			#%0100000000000000,INSTRUCTION
	andi.w			#%1110001111111111,INSTRUCTION	
	GETDATALENGTH	d0
	GETEA			a0
	move.l			(sp)+,INSTRUCTION
	
	; Move fpcr to ea
	btst			#12,INSTRUCTION
	beq.s			.NoFpcr
	lea.l			RegFpcrReserved,a1
	move.l			(a1),(a0)
	rts
	.NoFpcr:
	
	; Move fpsr to ea
	btst			#11,INSTRUCTION
	beq.s			.NoFpsr
	ifd	FPSR080
		; TODO: untested (implemented now in hw so should not be called)!
		fmove.l			fpsr,(a0)
	else
		lea.l			RegFpsrCc,a1
		move.l			(a1),(a0)
	endif
	rts
	.NoFpsr:
	
	; Move fpiar to ea
	lea.l			RegFpiar,a1
	move.l			(a1),(a0)
	jmp				UnsupportedHandler
	rts

	; Debug constants
	.DEBUGOP:
	dc.b 			"fmove fpcr,ea %08lx",10,0
	even
