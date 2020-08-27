;
; frestore emulation
;
FrestoreHandler

	; Debug instruction
	WRITEDEBUG		#.DEBUGOP,INSTRUCTION

	; Increment PC
	INREMENTPC		#$02

	; Get ea - temporarily faking data format so we can use ordinary functions
	move.l			INSTRUCTION,-(sp)
	ori.w			#%0100000000000000,INSTRUCTION
	andi.w			#%1110001111111111,INSTRUCTION	
	GETDATALENGTH	d0
	GETEA			a0
	move.l			(sp)+,INSTRUCTION
	
	; Emulate instruction (only null frames are supported atm and even that is nop)
	move.l			(a0),d0
    tst.l           d0
    beq.s           .RestoreOk
	lea		        ERRUNSUPPORTEDSFRAME,a0
	jmp		        Unsupported
    .RestoreOk:
	
	; Done
	rts
	
	; Debug constants
	.DEBUGOP:
	dc.b 			"frestore %08lx",10,0
	even