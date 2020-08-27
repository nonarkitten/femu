;
; fgetexp emulation
;
; TODO: de-normalized numbers must be normalized
; See: https://devel.rtems.org/browser/rtems/c/src/lib/libcpu/m68k/m68040/fpsp/sgetem.S
;
FgetexpHandler

	; Debug instruction
	WRITEDEBUG		#.DEBUGOP,INSTRUCTION

	; Increment PC
	INREMENTPC		#$04
	
	; Get data
	GETDATALENGTH	d0
	GETEAVALUE		d0,d1
	
	; Emulate instruction
	bfextu			d0{1:11},d0
	subi.w			#1023,d0
	jsr				LongToDouble
	
	; Write results
	GETREGISTER		d5
	MOVEDNTOFPN		d5,d0,d1
	
	; Set condition codes
	SETCC			d0,d1
	
	; Done
	rts
	
	; Debug constants
	.DEBUGOP:
	dc.b 			"fgetexp %08lx",10,0
	even
