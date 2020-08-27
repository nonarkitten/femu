;
; fgetman emulation
; 
; TODO: ATM this does not work. At all.
;
FgetmanHandler

	; Debug instruction
	WRITEDEBUG		#.DEBUGOP,INSTRUCTION

	; Increment PC
	INREMENTPC		#$04
	
	; Get data
	GETDATALENGTH	d0
	GETEAVALUE		d0,d1
	
	; Emulate instruction
	move.l			#-1023,d0
	bfins			d0,d0{1:11}
	
	; Write results
	GETREGISTER		d5
	MOVEDNTOFPN		d5,d0,d1
	
	; Set condition codes
	SETCC			d0,d1
	
	; Done
	rts
	
	; Debug constants
	.DEBUGOP:
	dc.b 			"fgetman %08lx",10,0
	even