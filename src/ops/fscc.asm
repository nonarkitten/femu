;
; fscc emulation
;
FsccHandler

	; Debug instruction
	WRITEDEBUG		#.DEBUGOP,INSTRUCTION
	
	; Increment PC
	INREMENTPC			#$04

	; Get ea
	move.l				INSTRUCTION,-(sp)
	ori.w				#%0101100000000000,INSTRUCTION
	andi.w				#%1111101111111111,INSTRUCTION
	GETDATALENGTH		d0
	GETEA				a0
	move.l				(sp)+,INSTRUCTION
	
	; Jump to predicate handler
	bfextu				INSTRUCTION{26:6},d0
	TESTCONDITION		.True,.False
	
	; False handler
	.False:
	move.b				#%00000000,(a0)
	rts
	
	; True handler
	.True:
	move.b				#%11111111,(a0)
	rts
	
	; Debug constants
	.DEBUGOP:
	dc.b 			"fscc %08lx",10,0
	even