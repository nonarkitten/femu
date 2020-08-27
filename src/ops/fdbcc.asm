;
; fdbcc emulation
;
FdbccHandler

	; Debug instruction
	WRITEDEBUG		#.DEBUGOP,INSTRUCTION
	
	; Jump to predicate handler
	bfextu				INSTRUCTION{26:6},d0
	TESTCONDITION		.True,.False
	
	; False handler
	.False:
	bfextu				INSTRUCTION{13:3},d0
	move.l				(OSTACKDN,STACKFRAME,d0.w*4),d1
	subi.w				#1,d1	
	move.l				d1,(OSTACKDN,STACKFRAME,d0.w*4)
	cmp.w				#-1,d1
	beq.s				.True
	move.w				$04(FAULTPC),d0
	ext.l				d0
	addi.l				#4,d0
	INREMENTPC			d0
		move.l				FAULTPC,$02(STACKFRAME) ; TODO: testing 040 ea from stack...
	rts
	
	; True handler
	.True:
	INREMENTPC			#$06
	rts
	
	; Debug constants
	.DEBUGOP:
	dc.b 			"fdbcc %08lx",10,0
	even