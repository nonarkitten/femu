;
; fbcc word emulation
;
FbccWordHandler

	; Debug instruction
	WRITEDEBUG		#.DEBUGOP,INSTRUCTION
	
	; Jump to predicate handler
	bfextu				INSTRUCTION{10:6},d0
	TESTCONDITION		.True,.False
	
	; False handler
	.False:
	INREMENTPC			#4
	rts
	
	; True handler
	.True:
	move.w				INSTRUCTION,d0
	ext.l				d0
	addi.l				#2,d0
	INREMENTPC			d0
		move.l				FAULTPC,$02(STACKFRAME) ; TODO: testing 040 ea from stack...
	rts
		
	; Debug constants
	.DEBUGOP:
	dc.b 			"fbcc.w %08lx",10,0
	even	

	
;
; fbcc long emulation
;
FbccLongHandler

	; Debug instruction
	WRITEDEBUG	#DEBUGINSTRUCTION,INSTRUCTION

	; Jump to predicate handler
	bfextu				INSTRUCTION{10:6},d0
	TESTCONDITION		.True,.False

	; False handler
	.False:
	INREMENTPC			#6
	rts
	
	; True handler
	.True:
	move.l				$02(FAULTPC),d0
	addi.l				#2,d0
	INREMENTPC			d0
		move.l				FAULTPC,$02(STACKFRAME) ; TODO: testing 040 ea from stack...
	rts
	
	; Debug constants
	.DEBUGOP:
	dc.b 			"fbcc.l %08lx",10,0
	even
