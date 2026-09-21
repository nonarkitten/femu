;
;
;
FSUBHANDLER macro

	; Debug instruction
	WRITEDEBUG		#.DEBUGOP,INSTRUCTION

	; Increment PC
	INREMENTPC		#$04

	; Get data
	GETDATALENGTH	d0
    ifnb \1
        MOVEFROMC       010,3
        vperm           #$01230123,d3,d3,d2
	else
		GETEAVALUE		d2,d3
	endif
	GETREGISTER		d5
	MOVEFPNTODN		d5,d0,d1
	
	; Emulate instruction
	ifd NOMATHLIB
		bchg			#31,d2
		FE_FADD
	else
		movea.l			MathIeeeDoubBasBase,a6
		jsr				_LVOIEEEDPSub(a6)
	endif

	; Write results
	GETREGISTER		d5
	MOVEDNTOFPN		d5,d0,d1

	; Set condition codes
	SETCC			d0,d1
	
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
