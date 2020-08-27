;
; femu - A FPU emulator
;
; This program implements a custom exception handler for F-line exceptions.
; The handler will then implement missing FPU instructions by sofware - hence 
; this program can be considered to be a FPU emulator. 
;
; Femu targets to 68040 and 6888x compatibility so actually femu is more powerful
; than either one alone. However, femu uses internally double precision math so 
; it's less precise than real FPU.
;
; Since this is software based emulator performance will be an issue. Expect this 
; to be usable only for software which does not use FPU much or with modern CPUs 
; like Apollo Core 68080. 
;
; Please also notice that this program is in alpha state and lot's of things are 
; still missing, buggy or outright wrong. You are welcome to contribute of course!
; 
; For UAE debugger:
;   w 0 $100 1 W
;   clr.w $100
;
; Author: Jari Eskelinen <jari.eskelinen@iki.fi>
; Contributors: flype, tuko, gvb, henrik
;
    jmp         FemuMain
    include		"utils/constants.asm"
	include		"utils/debug.asm"
	include		"utils/double.asm"
	include		"utils/macros.asm"
	include		"utils/fhandler.asm"
	include		"utils/fpu.asm"
	include		"utils/op.asm"
	include		"utils/ea.asm"
	include		"utils/math64.asm"
	include		"utils/type.asm"
	include		"ops/fabs.asm"
	include		"ops/facos.asm"
	include		"ops/fadd.asm"
	include		"ops/fasin.asm"
	include		"ops/fatan.asm"
	include		"ops/fbcc.asm"
	include		"ops/fgetexp.asm"
	include		"ops/fgetman.asm"
	include		"ops/fscc.asm"
	include		"ops/fcmp.asm"
	include		"ops/fcos.asm"
	include		"ops/fcosh.asm"
	include		"ops/fdbcc.asm"
	include		"ops/fdiv.asm"
	include		"ops/fetox.asm"
	include		"ops/fint.asm"
	include		"ops/fintrz.asm"
	include		"ops/flogn.asm"
	include		"ops/flog2.asm"
	include		"ops/flog10.asm"
	include		"ops/fmove.asm"
	include		"ops/fmovefpcr.asm"
	include		"ops/fmovecr.asm"
	include		"ops/fmovem.asm"
	include		"ops/fmul.asm"
	include		"ops/fneg.asm"
	include		"ops/frestore.asm"
	include		"ops/fsave.asm"
	include		"ops/fscale.asm"
	include		"ops/fsin.asm"
	include		"ops/fsincos.asm"
	include		"ops/fsinh.asm"
	include		"ops/fsub.asm"
	include		"ops/fsqrt.asm"
	include		"ops/ftentox.asm"
	include		"ops/ftan.asm"
	include		"ops/ftanh.asm"
	include		"ops/ftst.asm"
	include		"ops/ftwotox.asm"
	include		"ops/unsupported.asm"
	ifd VECTOR080
		include		"ops/fabs080.asm"
		include		"ops/fadd080.asm"
		include		"ops/fdiv080.asm"
		include		"ops/fmul080.asm"
		include		"ops/fsub080.asm"
	endif
	DOSBase:				dc.l	0
	MathIeeeDoubBasBase:	dc.l	0
	MathIeeeDoubTransBase:	dc.l	0
	AttnFlags:				dc.w	0
	ExceptionVector:		dc.l	0

	
;
; Main.
;
FemuMain

	; Initialize
	jsr			FemuInit
	tst.l		d0
	bne.s		.Error
	
	; Wait for a break signal
	move.l		_AbsExecBase,a6
	move.l		#SIGBREAKF,d0
	jsr			_LVOWait(a6)

	; Successful exit
	jsr			FemuExit
	move.l		#0,d0
	rts

	; Unsuccessful exit
	.Error:
	jsr			FemuExit
	move.l		#30,d0
	rts
	
	
;
; Initializes femu. 
;
FemuInit

	; Get AttnFlags and modify AttnFlags
	movea.l		_AbsExecBase,a6
	move.w		_LVOAttnFlags(a6),d0
	move.w		d0,AttnFlags
	ori.w		#$70,d0
	move.w		d0,_LVOAttnFlags(a6)
	
	; Open libraries
	OPENLIB 	DOSName,36,DOSBase,.LibError
	OPENLIB 	MathIeeeDoubBasName,45,MathIeeeDoubBasBase,.LibError,ERRLIBMATHBAS
	OPENLIB 	MathIeeeDoubTransName,45,MathIeeeDoubTransBase,.LibError,ERRLIBMATHTRANS
	
	; Check CPU 
	move.w		AttnFlags,d0
	ifd	CPU020
		btst		#AFB_68020,d0
		beq.w		.CpuError
		btst		#AFB_68040,d0
		bne.w		.CpuError
	endif
	ifd	CPU040
		btst		#AFB_68040,d0
		beq.w		.CpuError
		btst		#AFB_68080,d0
		bne.w		.CpuError
	endif
	ifd	CPU080
		btst		#AFB_68080,d0
		beq.w		.CpuError
	endif
	btst		#AFB_68881,d0
	bne.w		.FpuError
	
	; Get and modify the exception vector 
	jsr			GetVbrBase
	move.l		$2c(a0),ExceptionVector
	lea.l		HandleException(pc),a1
	move.l		a1,$2c(a0)
	
	; Initialize 080
	ifd CPU080
		jsr			Init080
	endif
	
	; Done
	WRITEOUT	#VERSTRING
	move.l		#0,d0
	rts
	
	; Library error
	.LibError:
	move.l		#30,d0
	rts
	
	; CPU error
	.CpuError:
	WRITEOUT	#ERRUNSUPPORTEDCPU
	move.l		#31,d0
	rts
	
	; FPU error
	.FpuError:
	WRITEOUT	#ERRFPUPRESENT
	move.l		#32,d0
	rts
	
;
; Cleans up femu - restores the exception vector and 
; AttnFlags and closes all open resources.
;
FemuExit

	; Exit 080
	ifd CPU080
		jsr			Exit080
	endif

	; Restore the exception vector
	tst.l		ExceptionVector
	beq.s		.ExceptionVectorOk
	move.w		AttnFlags,d0
	jsr			GetVbrBase
	move.l		ExceptionVector,$2c(a0)
	.ExceptionVectorOk:
	
	; Close libraries
	CLOSELIB	MathIeeeDoubTransBase
	CLOSELIB	MathIeeeDoubBasBase
	CLOSELIB	DOSBase
		
	; Restore AttnFlags
	tst.l		AttnFlags
	beq.s		.AttnFlagsOk
	movea.l		_AbsExecBase,a6
	move.w		AttnFlags,_LVOAttnFlags(a6)
	.AttnFlagsOk:

	; Done
	rts


;
; Initializes 080 
;
; TODO: store original values and restore them on exit
;
Init080

	; Initialize 080 fpu vectors
	ifd VECTOR080
		jsr          Initialize080FpuVectors
	endif
	
	; Supervisor mode inits
	movem.l		a5/a6,-(sp)
	movea.l		_AbsExecBase,a6
	lea.l		.Init080Super(pc),a5
	jsr			_LVOSupervisor(a6)
	movem.l		(sp)+,a5/a6
		
	; Done
	rts
	
	.Init080Super:
	
		; Disable DFP
		MOVEFROMC	08,08
		bclr		#1,d0
		MOVETOC		08,08
		rte
	

	
;
; Exits 080
;
Exit080

	; Supervisor mode exits
	movem.l		a5/a6,-(sp)
	movea.l		_AbsExecBase,a6
	lea.l		.Exit080Super(pc),a5
	jsr			_LVOSupervisor(a6)
	movem.l		(sp)+,a5/a6
	
	; Done
	rts
	
	.Exit080Super:
	
		; Enable DFP
		MOVEFROMC	08,08
		bset		#1,d0
		MOVETOC		08,08
		rte
	
	
;
; Gets the VBR base address.
;
; INPUTS
;	d0 -- AttnFlags
;
; RESULT
;	a0 -- The VBR base address.
;	
GetVbrBase
	movem.l		a5/a6,-(sp)
	movea.l		_AbsExecBase,a6
	lea.l		.GetVbrRegister(pc),a5
	jsr			_LVOSupervisor(a6)
	movem.l		(sp)+,a5/a6
	rts
	.GetVbrRegister:
	movec		vbr,a0
	rte

	
;
; Initializes 080 fpu vectors.
;
Initialize080FpuVectors
	ifd VECTOR080
		movea.l		_AbsExecBase,a6
		lea.l		.Super(pc),a5
		jsr			_LVOSupervisor(a6)
		rts
		
		.Super:
		lea.l        DirectOpVectorsAligned,a0
		MOVETOC      8,810
		rte
	endif

	
;
; Pre-exception registers. We write everything to memory before the instruction 
; is emulated and restore registers just before returning from exception. 
; Please notice that these are on the bottom on purpose for avoiding cache 
; problems.
;
; TODO: Use stack for this too?
;
			cnop	64,4
TempEa		dc.l	0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
