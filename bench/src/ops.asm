;
; Test opcode blob for the bench harness.
;
; Each line assembles to exactly one 68881 register-to-register FP
; instruction (2 words = 4 bytes -- verified by the harness, which
; refuses to run if that assumption ever breaks). The harness slices
; this flat binary into 4-byte chunks in the SAME ORDER as
; vectors/ops.txt lists its rows -- the two files are hand-kept in
; lockstep (see bench/README.md) rather than generated, since the set
; of opcodes under test is small and changes rarely.
;
; Register convention used throughout: fp0 holds the "a" (destination)
; operand, fp1 holds the "b" (source) operand when a vector has one.
; Dyadic ops use "op.x fp1,fp0" (fp0 := fp0 op fp1); monadic ops use
; "op.x fp0,fp0" (in place).
;
	fadd.x		fp1,fp0
	fsub.x		fp1,fp0
	fmul.x		fp1,fp0
	fdiv.x		fp1,fp0
	fabs.x		fp0,fp0
	fneg.x		fp0,fp0
	fint.x		fp0,fp0
	fintrz.x	fp0,fp0
	fsqrt.x		fp0,fp0
	facos.x		fp0,fp0
	fasin.x		fp0,fp0
	fatan.x		fp0,fp0
	fcos.x		fp0,fp0
	fcosh.x		fp0,fp0
	fetox.x		fp0,fp0
	ftentox.x	fp0,fp0
	ftwotox.x	fp0,fp0
	flog2.x		fp0,fp0
	flog10.x	fp0,fp0
	flogn.x		fp0,fp0
	fsin.x		fp0,fp0
	fsinh.x		fp0,fp0
	ftan.x		fp0,fp0
	ftanh.x		fp0,fp0
