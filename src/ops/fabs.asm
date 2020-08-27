FABSHANDLER macro

	; Debug instruction
	WRITEDEBUG		#.DEBUGOP,INSTRUCTION

	; Increment PC
	INREMENTPC		#$04
	
	; Get data
	GETDATALENGTH	d0
    ifnb \1
        MOVEFROMC       010,1
        vperm           #$01230123,d1,d1,d0
	else
		GETEAVALUE		d0,d1
	endif
	
	; Emulate instruction
	bclr			#31,d0
	
	; Write results
	GETREGISTER		d5
	MOVEDNTOFPN		d5,d0,d1
	
	; Set condition codes
	SETCC			d0,d1
	
endm


;
;
;
FabsHandler
FsabsHandler
FdabsHandler
	FABSHANDLER
	rts
	.DEBUGOP:
	dc.b 			"fabs %08lx",10,0
	even
