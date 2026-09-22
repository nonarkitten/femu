;
;
;
FSUBHANDLER macro

	; Debug instruction
	WRITEDEBUG		#.DEBUGOP,INSTRUCTION

	; Increment PC
	INREMENTPC		#$04

	; Get data. Same d3/d4/d5(source)+d0/d1/d2(dest) layout as FE_FADD's
	; caller in fadd.asm -- see there for why source is fetched first.
	GETDATALENGTH	d0
    ifnb \1
        MOVEFROMC       010,3
        vperm           #$01230123,d3,d3,d2
	else
		GETEAVALUE		d3,d4,d5
	endif
	GETREGISTER		d6
	MOVEFPNTODN		d6,d0,d1,d2

	; Emulate instruction (flip the source's sign bit, still bit31 of
	; its word0, then reuse FE_FADD as a-b = a+(-b))
	bchg			#31,d3
	FE_FADD

	; Write results
	GETREGISTER		d6
	MOVEDNTOFPN		d6,d0,d1,d2

	; Set condition codes
	SETCC			d0,d1,d2

endm


;
;
;
FsubHandler
FssubHandler
FdsubHandler
	FSUBHANDLER
	rts
	.DEBUGOP:
	dc.b 			"fsub %08lx",10,0
	even
