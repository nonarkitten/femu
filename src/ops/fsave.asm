;
; fsave emulation
;
FsaveHandler

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
	
	; Save null state frame (actually idle should be saved but format is not documented)
	stop #$2700
	move.l			$00,(a0)
	; Save idle state frame (format is unknown, just saving something seen in UAE)
	;move.l			$41000000,(a0)
	
	; Done
	rts
	
	; Debug constants
	.DEBUGOP:
	dc.b 			"fsave %08lx",10,0
	even