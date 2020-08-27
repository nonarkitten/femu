	jmp						Ftest
	include					"utils/constants.asm"
	include					"utils/fpu.asm"
	include					"utils/math64.asm"
	include					"utils/macros.asm"
	DOSBase:				dc.l	0
	MathIeeeDoubBasBase:	dc.l	0
	MathIeeeDoubTransBase:	dc.l	0
	rts
	
	



	
;
; 
;
Ftest




	movea.l		_AbsExecBase,a6
	lea.l		.Super(pc),a5
	jsr			_LVOSupervisor(a6)
	rts
	
	.Super:
	
	clr.w $100
	lea.l	.DING,a0
	fabs	#1,fp0
	fsave (a0)
	clr.w $100
	rte
	.DING:
	dc.l $ffffffff,$ffffffff,$ffffffff,$ffffffff,$ffffffff
	


	
	
	fmove.x		#1.1,fp0
	fmove.x		#2.2,fp1
	fmove.x		#3.3,fp2
	fmove.x		#4.4,fp3
	fmove.x		#5.5,fp4
	fmove.x		#6.6,fp5
	fmove.x		#7.7,fp6
	fmove.x		#8.8,fp7
	fmovem.x		fp0-fp7,-(sp)
	fmovem.x		.DaigaDaiga,fp0-fp7
	fmovem.x		(sp)+,fp0-fp7
	fmovem.x		fp0-fp7,.DaigaDaiga


	clr.w $100
	rte
	.DaigaDaiga:	dc.l 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0


	rts
	
	
	jsr FtestInit
	jsr FtestMathBase
	jsr FtestMathTrans
	jsr FtestCompare
	jsr FtestExit
	rts

	
;
; Comparison operator tests
;
FtestCompare

	movea.l				DOSBase,a6
	move.l				#compare_banner,d1
	move.l				#0,d2	
	jsr					_LVOVPrintf(a6)
	jmp					compare_banner_done
	compare_banner:	dc.b 10,"COMPARE",10,"-------",10,0
	compare_banner_done:
	
	Ftest_fcmp_lt:
	fmove.d			#10.50,fp0
	fmove.d			#10.49,fp1
	move.l			#$08000000,d0
	fmove.x			fp1,fp3
	fcmp.x			fp0,fp3
	fmove.l			fpsr,d1
	lea.l			fcmp_lt_msg,a0
	jsr				FtestCompare_result
	jmp			Ftest_fcmp_lt_done
	fcmp_lt_msg:	dc.b "fcmp",9,0
	Ftest_fcmp_lt_done:	
	
	Ftest_fcmp_eq:
	fmove.d			#11.50,fp0
	fmove.d			#11.50,fp1
	move.l			#$04000000,d0
	fmove.x			fp1,fp3
	fcmp.x			fp0,fp3
	fmove.l			fpsr,d1
	lea.l			fcmp_eq_msg,a0
	jsr				FtestCompare_result
	jmp			Ftest_fcmp_eq_done
	fcmp_eq_msg:	dc.b "fcmp",9,0
	Ftest_fcmp_eq_done:	
	
	Ftest_fcmp_gt:
	fmove.d			#12.40,fp0
	fmove.d			#12.50,fp1
	move.l			#0,d0
	fmove.x			fp1,fp3
	fcmp.x			fp0,fp3
	fmove.l			fpsr,d1
	lea.l			fcmp_gt_msg,a0
	jsr				FtestCompare_result
	jmp			Ftest_fcmp_gt_done
	fcmp_gt_msg:	dc.b "fcmp",9,0
	Ftest_fcmp_gt_done:	
	
	rts
	
;
; Base math tests
;
FtestMathBase

	movea.l				DOSBase,a6
	move.l				#mathbase_banner,d1
	move.l				#0,d2	
	jsr					_LVOVPrintf(a6)
	jmp					mathbase_banner_done
	mathbase_banner:	dc.b 10,"MATH BASE",10,"---------",10,0
	mathbase_banner_done:
	
	Ftest_fabs:
	fmove.d			#-5.5,fp0
	fmove.d			#0,fp1
	fmove.d			#5.5,fp2
	fmove.x			fp1,fp3
	fabs.x			fp0,fp3
	lea.l			fabs_msg,a0
	jsr				Ftest_math_result
	jmp			fabs_done
	fabs_msg:		dc.b "fabs",9,0
	fabs_done:
	
	fmove.d			#-5.5,fp0
	fmove.d			#0,fp1
	fmove.d			#5.5,fp2
	fmove.x			fp1,fp3
	fsabs.x			fp0,fp3
	lea.l			fsabs_msg,a0
	jsr				Ftest_math_result
	jmp			fsabs_done
	fsabs_msg:		dc.b "fsabs",9,0,0
	fsabs_done:
	
	fmove.d			#-5.5,fp0
	fmove.d			#0,fp1
	fmove.d			#5.5,fp2
	fmove.x			fp1,fp3
	fdabs.x			fp0,fp3
	lea.l			fdabs_msg,a0
	jsr				Ftest_math_result
	jmp			fdabs_done
	fdabs_msg:		dc.b "fdabs",9,0,0
	fdabs_done:
	
	fmove.d			#1.1,fp0
	fmove.d			#2.2,fp1
	fmove.d			#3.3,fp2
	fmove.x			fp1,fp3
	fadd.x			fp0,fp3
	lea.l			fadd_msg,a0
	jsr				Ftest_math_result
	jmp			fadd_done
	fadd_msg:		dc.b "fadd",9,0
	fadd_done:
	
	fmove.d			#1.1,fp0
	fmove.d			#2.2,fp1
	fmove.d			#3.3,fp2
	fmove.x			fp1,fp3
	fsadd.x			fp0,fp3
	lea.l			fsadd_msg,a0
	jsr				Ftest_math_result
	jmp			fsadd_done
	fsadd_msg:		dc.b "fsadd",9,0,0
	fsadd_done:
	
	fmove.d			#1.1,fp0
	fmove.d			#2.2,fp1
	fmove.d			#3.3,fp2
	fmove.x			fp1,fp3
	fdadd.x			fp0,fp3
	lea.l			fdadd_msg,a0
	jsr				Ftest_math_result
	jmp			fdadd_done
	fdadd_msg:		dc.b "fdadd",9,0,0
	fdadd_done:
	
	fmove.d			#2.5,fp0
	fmove.d			#25.25,fp1
	fmove.d			#10.1,fp2
	fmove.x			fp1,fp3
	fdiv.x			fp0,fp3
	lea.l			fdiv_msg,a0
	jsr				Ftest_math_result
	jmp			fdiv_done
	fdiv_msg:		dc.b "fdiv",9,0
	fdiv_done:
	
	fmove.d			#2.5,fp0
	fmove.d			#25.25,fp1
	fmove.d			#10.1,fp2
	fmove.x			fp1,fp3
	fsdiv.x			fp0,fp3
	lea.l			fsdiv_msg,a0
	jsr				Ftest_math_result
	jmp			fsdiv_done
	fsdiv_msg:		dc.b "fsdiv",9,0,0
	fsdiv_done:

	fmove.d			#2.5,fp0
	fmove.d			#25.25,fp1
	fmove.d			#10.1,fp2
	fmove.x			fp1,fp3
	fddiv.x			fp0,fp3
	lea.l			fddiv_msg,a0
	jsr				Ftest_math_result
	jmp			fddiv_done
	fddiv_msg:		dc.b "fddiv",9,0,0
	fddiv_done:
	
	fmove.d			#2.5,fp0
	fmove.d			#25.25,fp1
	fmove.d			#10.1,fp2
	fmove.x			fp1,fp3
	fsgldiv.x		fp0,fp3
	lea.l			fsgldiv_msg,a0
	jsr				Ftest_math_result
	jmp			fsgldiv_done
	fsgldiv_msg:	dc.b "fsgldiv",9,0,0	
	fsgldiv_done:
	
	fmove.d			#2.9,fp0
	fmove.d			#0,fp1
	fmove.d			#3,fp2
	fmove.x			fp1,fp3
	fint.x			fp0,fp3
	lea.l			fint_msg,a0
	jsr				Ftest_math_result
	jmp			fint_done
	fint_msg:	dc.b "fint",9,0
	fint_done:

	fmove.d			#2.9,fp0
	fmove.d			#0,fp1
	fmove.d			#2,fp2
	fmove.x			fp1,fp3
	fintrz.x		fp0,fp3
	lea.l			fintrz_msg,a0
	jsr				Ftest_math_result
	jmp			fintrz_done
	fintrz_msg:	dc.b "fintrz",9,0
	fintrz_done:

	fmove.d			#12.1,fp0
	fmove.d			#2.25,fp1
	fmove.d			#27.225,fp2
	fmove.x			fp1,fp3
	fmul.x			fp0,fp3
	lea.l			fmul_msg,a0
	jsr				Ftest_math_result
	jmp			fmul_done
	fmul_msg:		dc.b "fmul",9,0
	fmul_done:
	
	fmove.d			#12.1,fp0
	fmove.d			#2.25,fp1
	fmove.d			#27.225,fp2
	fmove.x			fp1,fp3
	fsmul.x			fp0,fp3
	lea.l			fsmul_msg,a0
	jsr				Ftest_math_result
	jmp			fsmul_done
	fsmul_msg:		dc.b "fsmul",9,0,0
	fsmul_done:
	
	fmove.d			#12.1,fp0
	fmove.d			#2.25,fp1
	fmove.d			#27.225,fp2
	fmove.x			fp1,fp3
	fdmul.x			fp0,fp3
	lea.l			fdmul_msg,a0
	jsr				Ftest_math_result
	jmp			fdmul_done
	fdmul_msg:		dc.b "fdmul",9,0,0
	fdmul_done:
	
	fmove.d			#12.1,fp0
	fmove.d			#0,fp1
	fmove.d			#-12.1,fp2
	fmove.x			fp1,fp3
	fneg.x			fp0,fp3
	lea.l			fneg_msg,a0
	jsr				Ftest_math_result
	jmp			fneg_done
	fneg_msg:		dc.b "fneg",9,0
	fneg_done:
	
	fmove.d			#12.1,fp0
	fmove.d			#0,fp1
	fmove.d			#-12.1,fp2
	fmove.x			fp1,fp3
	fsneg.x			fp0,fp3
	lea.l			fsneg_msg,a0
	jsr				Ftest_math_result
	jmp			fsneg_done
	fsneg_msg:		dc.b "fsneg",9,0,0
	fsneg_done:
	
	fmove.d			#12.1,fp0
	fmove.d			#0,fp1
	fmove.d			#-12.1,fp2
	fmove.x			fp1,fp3
	fdneg.x			fp0,fp3
	lea.l			fdneg_msg,a0
	jsr				Ftest_math_result
	jmp			fdneg_done
	fdneg_msg:		dc.b "fdneg",9,0,0
	fdneg_done:
	
	fmove.d			#120.1,fp0
	fmove.d			#50.2,fp1
	fmove.d			#-69.9,fp2
	fmove.x			fp1,fp3
	fsub.x			fp0,fp3
	lea.l			fsub_msg,a0
	jsr				Ftest_math_result
	jmp			fsub_done
	fsub_msg:		dc.b "fsub",9,0
	fsub_done:
	
	fmove.d			#120.1,fp0
	fmove.d			#50.2,fp1
	fmove.d			#-69.9,fp2
	fmove.x			fp1,fp3
	fssub.x			fp0,fp3
	lea.l			fssub_msg,a0
	jsr				Ftest_math_result
	jmp			fssub_done
	fssub_msg:		dc.b "fssub",9,0,0
	fssub_done:
	
	fmove.d			#120.1,fp0
	fmove.d			#50.2,fp1
	fmove.d			#-69.9,fp2
	fmove.x			fp1,fp3
	fdsub.x			fp0,fp3
	lea.l			fdsub_msg,a0
	jsr				Ftest_math_result
	jmp			fdsub_done
	fdsub_msg:		dc.b "fdsub",9,0,0	
	fdsub_done:
	
	rts


;
; Transcendental math tests 
;
FtestMathTrans

	movea.l				DOSBase,a6
	move.l				#mathtrans_banner,d1
	move.l				#0,d2	
	jsr					_LVOVPrintf(a6)
	jmp					mathtrans_banner_done
	mathtrans_banner:	dc.b 10,"MATH TRANS",10,"---------",10,0,0
	mathtrans_banner_done:
	
	fmove.d			#0.72,fp0
	fmove.d			#0,fp1
	fmove.d			#0.7669940078618667,fp2 
	fmove.x			fp1,fp3
	facos.x			fp0,fp3
	lea.l			facos_msg,a0
	jsr				Ftest_math_result
	jmp			facos_done
	facos_msg:		dc.b "facos",9,0,0
	facos_done:
		
	fmove.d			#0.71,fp0
	fmove.d			#0,fp1
	fmove.d			#0.7894982093461719,fp2 
	fmove.x			fp1,fp3
	fasin.x			fp0,fp3
	lea.l			fasin_msg,a0
	jsr				Ftest_math_result
	jmp			fasin_done
	fasin_msg:		dc.b "fasin",9,0,0
	fasin_done:
	
	fmove.d			#2.25,fp0
	fmove.d			#0,fp1
	fmove.d			#1.1525719972156676,fp2 
	fmove.x			fp1,fp3
	fatan.x			fp0,fp3
	lea.l			fatan_msg,a0
	jsr				Ftest_math_result
	jmp			fatan_done
	fatan_msg:		dc.b "fatan",9,0,0
	fatan_done:
	
	fmove.d			#0.75,fp0
	fmove.d			#0,fp1
	fmove.d			#0.7316888688738209,fp2 
	fmove.x			fp1,fp3
	fcos.x			fp0,fp3
	lea.l			fcos_msg,a0
	jsr				Ftest_math_result
	jmp			fcos_done
	fcos_msg:		dc.b "fcos",9,0
	fcos_done:
	
	fmove.d			#9.43,fp0
	fmove.d			#0,fp1
	fmove.d			#6228.263405943807,fp2 
	fmove.x			fp1,fp3
	fcosh.x			fp0,fp3
	lea.l			fcosh_msg,a0
	jsr				Ftest_math_result
	jmp			fcosh_done
	fcosh_msg:		dc.b "fcosh",9,0,0
	fcosh_done:
	
	fmove.d			#3.66,fp0
	fmove.d			#0,fp1
	fmove.d			#38.8613428713,fp2
	fmove.x			fp1,fp3
	fetox.x			fp0,fp3
	lea.l			fetox_msg,a0
	jsr				Ftest_math_result
	jmp			fetox_done
	fetox_msg:		dc.b "fetox",9,0,0
	fetox_done:
	
	fmove.d			#5.12,fp0
	fmove.d			#0,fp1
	fmove.d			#131825.673856,fp2
	fmove.x			fp1,fp3
	ftentox.x		fp0,fp3
	lea.l			ftentox_msg,a0
	jsr				Ftest_math_result
	jmp			ftentox_done
	ftentox_msg:	dc.b "ftentox",9,0,0
	ftentox_done:
	
	fmove.d			#12.5,fp0
	fmove.d			#0,fp1
	fmove.d			#5792.618751480198,fp2
	fmove.x			fp1,fp3
	ftwotox.x		fp0,fp3
	lea.l			ftwotox_msg,a0
	jsr				Ftest_math_result
	jmp			ftwotox_done
	ftwotox_msg:	dc.b "ftwotox",9,0,0
	ftwotox_done:
	
	fmove.d			#7.25,fp0
	fmove.d			#0,fp1
	fmove.d			#2.8579809951275723,fp2
	fmove.x			fp1,fp3
	flog2.x			fp0,fp3
	lea.l			flog2_msg,a0
	jsr				Ftest_math_result
	jmp			flog2_done
	flog2_msg:		dc.b "flog2",9,0,0
	flog2_done:

	fmove.d			#7.25,fp0
	fmove.d			#0,fp1
	fmove.d			#0.8603380065709937,fp2
	fmove.x			fp1,fp3
	flog10.x		fp0,fp3
	lea.l			flog10_msg,a0
	jsr				Ftest_math_result
	jmp			flog10_done
	flog10_msg:	dc.b "flog10",9,0
	flog10_done:

	fmove.d			#7.25,fp0
	fmove.d			#0,fp1
	fmove.d			#1.9810014688665833,fp2
	fmove.x			fp1,fp3
	flogn.x			fp0,fp3
	lea.l			flogn_msg,a0
	jsr				Ftest_math_result
	jmp			flogn_done
	flogn_msg:		dc.b "flogn",9,0,0
	flogn_done:
	
	fmove.d			#0.25,fp0
	fmove.d			#0,fp1
	fmove.d			#0.24740395925452294,fp2
	fmove.x			fp1,fp3
	fsin.x			fp0,fp3
	lea.l			fsin_msg,a0
	jsr				Ftest_math_result
	jmp			fsin_done
	fsin_msg:		dc.b "fsin",9,0
	fsin_done:
	
	fmove.d			#8.62,fp0
	fmove.d			#0,fp1
	fmove.d			#2770.6931066087172,fp2
	fmove.x			fp1,fp3
	fsinh.x			fp0,fp3
	lea.l			fsinh_msg,a0
	jsr				Ftest_math_result
	jmp			fsinh_done
	fsinh_msg:		dc.b "fsinh",9,0,0
	fsinh_done:
	
	fmove.d			#4.25,fp0
	fmove.d			#0,fp1
	fmove.d			#2.0615528128088303,fp2
	fmove.x			fp1,fp3
	fsqrt.x			fp0,fp3
	lea.l			fsqrt_msg,a0
	jsr				Ftest_math_result
	jmp			fsqrt_done
	fsqrt_msg:		dc.b "fsqrt",9,0,0
	fsqrt_done:
	
	fmove.d			#4.25,fp0
	fmove.d			#0,fp1
	fmove.d			#2.0615528128088303,fp2
	fmove.x			fp1,fp3
	fssqrt.x		fp0,fp3
	lea.l			fssqrt_msg,a0
	jsr				Ftest_math_result
	jmp			fssqrt_done
	fssqrt_msg:	dc.b "fssqrt",9,0
	fssqrt_done:
	
	fmove.d			#4.25,fp0
	fmove.d			#0,fp1
	fmove.d			#2.0615528128088303,fp2
	fmove.x			fp1,fp3
	fdsqrt.x		fp0,fp3
	lea.l			fdsqrt_msg,a0
	jsr				Ftest_math_result
	jmp			fdsqrt
	fdsqrt_msg:	dc.b "fdsqrt",9,0
	fdsqrt:
	
	fmove.d			#3.91,fp0
	fmove.d			#0,fp1
	fmove.d			#0.9665829335238821,fp2
	fmove.x			fp1,fp3
	ftan.x			fp0,fp3
	lea.l			ftan_msg,a0
	jsr				Ftest_math_result
	jmp			ftan_done
	ftan_msg:		dc.b "ftan",9,0
	ftan_done:
	
	fmove.d			#6.11,fp0
	fmove.d			#0,fp1
	fmove.d			#0.9999901383568018,fp2
	fmove.x			fp1,fp3
	ftanh.x			fp0,fp3
	lea.l			ftanh_msg,a0
	jsr				Ftest_math_result
	jmp			ftanh_done
	ftanh_msg:		dc.b "ftanh",9,0,0
	ftanh_done:
	
	rts
	
	
;
; 
;
FtestInit
	movea.l		_AbsExecBase,a6
	lea.l		DOSName,a1 
	move.l		#$24,d0
	jsr			_LVOOpenLibrary(a6)
    move.l		d0,DOSBase
	rts

	
;
; 
;
FtestExit
	movea.l		_AbsExecBase,a6
	movea.l		DOSBase,a1
	jsr			_LVOCloseLibrary(a6)
	rts
	
	
;
; Outputs result of compare test case.
;
; INPUTS
;	a0 -- Name of the operation
;	fp0 -- Left operand value
;	fp1 -- Right operand value
;	d0 -- Expected status register 
;	d1 -- Result status register
;	
FtestCompare_result	

	; Populate argv 
	move.l		a0,FtestCompare_argv_op
	lea.l		FtestCompare_argv_operands,a0
	fmove.d		fp0,(a0)
	fmove.d		fp1,$08(a0)
	move.l		d0,$10(a0)
	move.l		d1,$14(a0)
	
	; Check result 
	cmp.l		d0,d1
	beq		FtestCompare_result_ok
	move.l		#FtestCompare_msg_fail,FtestCompare_argv_status
	bra.s		FtestCompare_result_done
	FtestCompare_result_ok:
	move.l		#FtestCompare_msg_ok,FtestCompare_argv_status
	FtestCompare_result_done:	

	; Output results
	movea.l		DOSBase,a6
	move.l		#FtestCompare_msg_fmt,d1
	move.l		#FtestCompare_argv_op,d2	
	jsr			_LVOVPrintf(a6)
	rts
	
	; Argv 
	FtestCompare_msg_ok:			dc.b	"OK",0
	FtestCompare_msg_fail:			dc.b	"FAIL",0
	FtestCompare_msg_fmt:			dc.b	"%s %08lx%08lx %08lx%08lx %08lx %08lx %s",10,0,0
	FtestCompare_argv_op:			dc.l	0
	FtestCompare_argv_operands:		dc.l	0,0,0,0,0,0
	FtestCompare_argv_status:		dc.l	0

	
;
; Outputs result of math test case.
;
; INPUTS
;	a0 -- Name of the operation
;	fp0 -- Source operand value
;	fp1 -- Destination operand value
;	fp2 -- Expected result
;	fp3 -- Result
;	
Ftest_math_result	

	; Convert expected result and result to single and back to 
	; in order double to get rid of rounding errors
	fmove.s	fp2,__fp2
	fmove.s	__fp2,fp2
	fmove.s	fp3,__fp3
	fmove.s	__fp3,fp3
	
	; Populate argv 
	move.l		a0,Ftest_math_argv_op
	lea.l		Ftest_math_argv_operands,a0
	fmove.d		fp0,(a0)
	fmove.d		fp1,$08(a0)
	fmove.d		fp3,$10(a0)
	fmove.d		fp2,$18(a0)

	; Check result 
	fcmp.x		fp2,fp3
	fbeq		Ftest_math_result_ok
	move.l		#Ftest_math_msg_fail,Ftest_math_argv_status
	bra.s		Ftest_math_result_done
	Ftest_math_result_ok:
	move.l		#Ftest_math_msg_ok,Ftest_math_argv_status
	Ftest_math_result_done:
	
	; Output results
	movea.l		DOSBase,a6
	move.l		#Ftest_math_msg_fmt,d1
	move.l		#Ftest_math_argv_op,d2	
	jsr			_LVOVPrintf(a6)
	rts
	
	; Argv 
	Ftest_math_msg_ok:			dc.b	"OK",0
	Ftest_math_msg_fail:		dc.b	"FAIL",0
	Ftest_math_msg_fmt:			dc.b	"%s %08lx%08lx %08lx%08lx %08lx%08lx %08lx%08lx %s",10,0,0
	Ftest_math_argv_op:			dc.l	0
	Ftest_math_argv_operands:	dc.l	0,0,0,0,0,0,0,0
	Ftest_math_argv_status:		dc.l	0
	
	; WIP
	__fp2:	dc.l	0,0,0,0
	__fp3:	dc.l	0,0,0,0

	
	
	
	
	
	
	
	
	
	
	
	
	
	
	
	
	
	
	
	
	
	
	
; TODO:
	move.l		#4,d6
	lea.l		indirect,a6

	move.l			(a6,d6.l*1),d0
	fmove.l			(a6,d6.l*1),fp0
	fmove.l			fp0,d1
	
	move.l			(d6.l*1),d0
	fmove.l			(d6.l*1),fp0
	fmove.l			fp0,d1
	
	move.l			($22,a6,d6.l*1),d0
	fmove.l			($22,a6,d6.l*1),fp0
	fmove.l			fp0,d1
	
	move.l			($22,d6.l*1),d0
	fmove.l			($22,d6.l*1),fp0
	fmove.l			fp0,d1
	
	move.l			($10000,a6,d6.l*1),d0
	fmove.l			($10000,a6,d6.l*1),fp0
	fmove.l			fp0,d1
	
	move.l			($10000,d6.l*1),d0
	fmove.l			($10000,d6.l*1),fp0
	fmove.l			fp0,d1
	
	move.l			([a6]),d0
	fmove.l			([a6]),fp0
	fmove.l			fp0,d1
	
	move.l			([a6],$22),d0
	fmove.l			([a6],$22),fp0
	fmove.l			fp0,d1
	
	move.l			([a6],$40000000),d0
	fmove.l			([a6],$40000000),fp0
	fmove.l			fp0,d1
	
	move.l			([$04,a6]),d0
	fmove.l			([$04,a6]),fp0
	fmove.l			fp0,d1
	
	move.l			([$04,a6],$22),d0
	fmove.l			([$04,a6],$22),fp0
	fmove.l			fp0,d1
	
	move.l			([$04,a6],$40000000),d0
	fmove.l			([$04,a6],$40000000),fp0
	fmove.l			fp0,d1
	
	move.l			([a6,d6.l*1]),d0
	fmove.l			([a6,d6.l*1]),fp0
	fmove.l			fp0,d1
	
	move.l			([a6,d6.l*1],$22),d0
	fmove.l			([a6,d6.l*1],$22),fp0
	fmove.l			fp0,d1
	
	move.l			([a6,d6.l*1],$40000000),d0
	fmove.l			([a6,d6.l*1],$40000000),fp0
	fmove.l			fp0,d1
	
	move.l			([d6.l*1]),d0
	fmove.l			([d6.l*1]),fp0
	fmove.l			fp0,d1
	
	move.l			([d6.l*1],$22),d0
	fmove.l			([d6.l*1],$22),fp0
	fmove.l			fp0,d1
	
	move.l			([d6.l*1],$40000000),d0
	fmove.l			([d6.l*1],$40000000),fp0
	fmove.l			fp0,d1
	
	move.l			([$04,a6,d6.l*1]),d0
	fmove.l			([$04,a6,d6.l*1]),fp0
	fmove.l			fp0,d1
	
	move.l			([$04,a6,d6.l*1],$22),d0
	fmove.l			([$04,a6,d6.l*1],$22),fp0
	fmove.l			fp0,d1
	
	move.l			([$04,a6,d6.l*1],$40000000),d0
	fmove.l			([$04,a6,d6.l*1],$40000000),fp0
	fmove.l			fp0,d1
	
	move.l			([$04,d6.l*1]),d0
	fmove.l			([$04,d6.l*1]),fp0
	fmove.l			fp0,d1
	
	move.l			([$04,d6.l*1],$22),d0
	fmove.l			([$04,d6.l*1],$22),fp0
	fmove.l			fp0,d1
	
	move.l			([$04,d6.l*1],$40000000),d0
	fmove.l			([$04,d6.l*1],$40000000),fp0
	fmove.l			fp0,d1
	
	move.l			([a6],d6.l*1),d0
	fmove.l			([a6],d6.l*1),fp0
	fmove.l			fp0,d1
	
	move.l			([a6],d6.l*1,$22),d0
	fmove.l			([a6],d6.l*1,$22),fp0
	fmove.l			fp0,d1
	
	move.l			([a6],d6.l*1,$40000000),d0
	fmove.l			([a6],d6.l*1,$40000000),fp0
	fmove.l			fp0,d1
	
	move.l			([$04,a6],d6.l*1),d0
	fmove.l			([$04,a6],d6.l*1),fp0
	fmove.l			fp0,d1
	
	move.l			([$04,a6],d6.l*1,$22),d0
	fmove.l			([$04,a6],d6.l*1,$22),fp0
	fmove.l			fp0,d1
	
	move.l			([$04,a6],d6.l*1,$40000000),d0
	fmove.l			([$04,a6],d6.l*1,$40000000),fp0
	fmove.l			fp0,d1

	move.l			([$04],d6.l*1),d0
	fmove.l			([$04],d6.l*1),fp0
	fmove.l			fp0,d1
	
	move.l			([$04],d6.l*1,$22),d0
	fmove.l			([$04],d6.l*1,$22),fp0
	fmove.l			fp0,d1
	
	move.l			([$04],d6.l*1,$40000000),d0
	fmove.l			([$04],d6.l*1,$40000000),fp0
	fmove.l			fp0,d1
	
	rts
	indirect: dc.l $110 ; contains value 00f8 1908
	indirect2: dc.l $120 ; contains value 00f8 1908
	indirect3: dc.l $130 ; contains value 00f8 1908
	