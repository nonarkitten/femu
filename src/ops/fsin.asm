;		if (x < -3.14159265)
;			x += 6.28318531;
;		else if (x >  3.14159265)
;			x -= 6.28318531;
; 
;		if ( x < 0 )
;			return x * ( 1.27323954+0.405284735f*x);
;		else
;			return x * ( 1.27323954-0.405284735f*x);

FE_FSIN macro


	fcmp.d	#-3.14159265,fp0
	fge.s	.\@NoLtPi
	fadd.d	#6.28318531f,fp0
	bra.s	.\@CmpZ
	.\@NoLtPi

	fcmp.d	#3.14159265,fp0
	fle.s	.\@NoGtPi
	fsub.d	#6.28318531f,fp0
	.\@NoGtPi
	
	.\@CmpZ:
	ftst.d	#0,fp0
	bge.s	.NoLtZ
	fmove.d	#1.27323954+0.405284735f,fp1
	fmul.x	fp0,fp1
	fmul.x	fp1,fp0	
	bra.s	.\@Ok
	.NoLtZ:
	
	fmove.d	#1.27323954-0.405284735f,fp1
	fmul.x	fp0,fp1
	fmul.x	fp1,fp0	
	
	.\@Ok:

endm


;
; fsin emulation
;
FsinHandler

	; Debug instruction
	WRITEDEBUG		#.DEBUGOP,INSTRUCTION

	; Increment PC
	INREMENTPC		#$04

	; Get data
	GETDATALENGTH	d0
	GETEAVALUE		d0,d1
	
	; Emulate instruction
	;ifd NOMATHLIB
	;	FE_FSIN
	;else
		movea.l			MathIeeeDoubTransBase,a6
		jsr				_LVOIEEEDPSin(a6)
	;endif

	; Write results
	GETREGISTER		d5
	MOVEDNTOFPN		d5,d0,d1

	; Set condition codes
	SETCC			d0,d1

	; Done
	rts
	
	; Debug constants
	.DEBUGOP:
	dc.b 			"fsin %08lx",10,0
	even	
