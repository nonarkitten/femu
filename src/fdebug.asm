Init
	movea.l		_AbsExecBase,a6
	lea.l		DOSName,a1 
	move.l		#$24,d0
	jsr			_LVOOpenLibrary(a6)
    move.l		d0,DOSBase
	
Debug
	fmove.l		#1,fp0
	lea.l		Testval,a0
	fadd.d		(a0),fp0
	fmovem.x	fp0,Argv
	
Dump
	movea.l		DOSBase,a6
	move.l		#Format,d1
	move.l		#Argv,d2	
	jsr			_LVOVPrintf(a6)

Exit
	movea.l		_AbsExecBase,a6
	movea.l		DOSBase,a1
	jsr			_LVOCloseLibrary(a6)
	move.l		0,d0
	rts
	
_AbsExecBase			equ		$04
_LVOOpenLibrary			equ		-$228
_LVOCloseLibrary		equ		-$19e
_LVOVPrintf				equ		-$3ba
Data					dc.l	$11223344,$55667788
DOSName					dc.b	"dos.library",0
DOSBase					dc.l	$00
Format					dc.b	"%08lx %08lx",10,0
Argv					dc.l	$ffffffff,$ffffffff,$ffffffff
Testval                 dc.l    $40000000,$00000000
