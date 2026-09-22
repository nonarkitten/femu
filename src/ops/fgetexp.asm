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
	
	; Get data (extended format, checklist #4: 15-bit exponent, bias 16383)
	GETDATALENGTH	d0
	GETEAVALUE		d0,d1,d2

	; Emulate instruction
	bfextu			d0{1:15},d0
	subi.w			#16383,d0
	jsr				LongToInternal

	; Write results
	GETREGISTER		d5
	MOVEDNTOFPN		d5,d0,d1,d2

	; Set condition codes
	SETCC			d0,d1,d2
	
	; Done
	rts
	
	; Debug constants
	.DEBUGOP:
	dc.b 			"fgetexp %08lx",10,0
	even
