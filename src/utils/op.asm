;
; Gets the length of the data of the instruction in bytes. Please notice
; that this works only for instructions which has source specifier field
; on usual location. Instructions with fixed lengths or instructions like
; fmovem are not covered.
;
; INPUTS
;	INSTRUCTION -- Instruction.
;
; RESULT
;	\1 -- Data length in bytes.
;
GETDATALENGTH macro

	; Register to register is always double
	btst.l		#14,INSTRUCTION
	bne.s		.NoRegReg
	move.l		#$08,\1
	bra.s		.GotLength
	.NoRegReg:
	
	; Get length from data format field
	bfextu		INSTRUCTION{19:3},\1
	move.l		(FMTLENGTHS,\1.w*4),\1
	.GotLength:

endm


;
; Gets number of the register of the instruction. Number is extracted from 
; usual register field of the instruction. If instruction does not have
; register field on usual location then location override can be given. 
;
; INPUTS
;	INSTRUCTION -- Instruction.
;	\2 -- Location.
;
; RESULT
;	\1 -- Register number.
;
GETREGISTER macro
	ifnb \2
		bfextu		INSTRUCTION{\2:3},\1
	else
		bfextu		INSTRUCTION{22:3},\1
	endif
endm	


;
; Emulates the instruction.
;
; INPUTS
;	INSTRUCTION -- Instruction.
;	FAULTPC -- Faulted PC.
;
EmulateInstruction

	; Make a jump based on bits 6...8 of the first word
    bfextu		INSTRUCTION{7:3},d0
    bfextu		INSTRUCTION{10:6},d3
    bfextu		INSTRUCTION{10:12},d4
	jmp			(OpBits0608Vectors,d0.w*4)
	
	; Bits 6...8 are 001, making final jump based on bits 0...5 of the first word
	OpBits0608001:
	jmp			(OpBits0005Vectors,d3.w*4)

	; Bits 6...8 of the first word are 000, checking if it's fmovecr and of not
	; then making another jump based on bits 13...15 of the second word
	OpBits0608000:
	bfextu		INSTRUCTION{16:3},d1
    bfextu		INSTRUCTION{25:7},d2
    cmp.b       #%000000000010111,d4
	beq.s		.FmoveCr
	jmp			(OpBits1315Vectors,d1.w*4)
	.FmoveCr:
	jsr			FmovecrHandler
	rts	   

	; Bits 13...15 of the second word are 0?0, making final jump based on bits 0...6 of the second word
	OpBits1315_000:
	OpBits1315_010:
	jmp			(OpBits0006Vectors,d2.w*4)


;
;  Instruction bits 6...8 vectors.
;
OpBits0608Vectors
	bra.w		OpBits0608000			; 000 fmove/fmovecr/fmovem/opmode
	bra.w		OpBits0608001			; 001 fscc/cpscc/fdbcc/cpdbcc/ftrapcc/cptrapcc
	bra.w		FbccWordHandler			; 010 fbcc.w
	bra.w		FbccLongHandler			; 011 fbcc.l
	bra.w		FsaveHandler			; 100 fsave/cpsave
	bra.w		FrestoreHandler			; 101 frestore/cprestore
	bra.w		UnsupportedHandler		; 110 unused
	bra.w		UnsupportedHandler		; 111 unused
	
	
;
;  Instruction bits 13...15 vectors.
;
OpBits1315Vectors
	bra.w		OpBits1315_000			; 000 opmode reg to reg
	bra.w		UnsupportedHandler		; 001 unused
	bra.w		OpBits1315_010			; 010 opmode ea to reg
	bra.w		FmoveRegEaHandler		; 011 fmove reg to ea
	bra.w		FmoveEaToFpcrHandler	; 100 fmove ea to fpcr
	bra.w		FmoveFpcrToEaHandler	; 101 fmove fpcr to ea
	bra.w		FmovemEaRegHandler		; 110 fmovem ea to reg 
	bra.w		FmovemRegEaHandler		; 111 fmovem reg to ea

	
;
;  Instruction bits 0...6 vectors.
;
OpBits0006Vectors
	bra.w		FmoveEaRegHandler	; 0000000 fmove
	bra.w		FintHandler			; 0000001 fint
	bra.w		FsinhHandler		; 0000010 fsinh
	bra.w		FintrzHandler		; 0000011 fintrz
	bra.w		FsqrtHandler		; 0000100 fsqrt
	bra.w		UnsupportedHandler	; 0000101
	bra.w		UnsupportedHandler	; 0000110
	bra.w		UnsupportedHandler	; 0000111
	bra.w		UnsupportedHandler	; 0001000
	bra.w		FtanhHandler		; 0001001 ftanh
	bra.w		FatanHandler		; 0001010 fatan
	bra.w		UnsupportedHandler	; 0001011
	bra.w		FasinHandler		; 0001100 fasin
	bra.w		UnsupportedHandler	; 0001101 
	bra.w		FsinHandler			; 0001110 fsin
	bra.w		FtanHandler			; 0001111 ftan
	bra.w		FetoxHandler		; 0010000 fetox
	bra.w		FtwotoxHandler		; 0010001 ftwotox
	bra.w		FtentoxHandler		; 0010010 ftentox
	bra.w		UnsupportedHandler	; 0010011
	bra.w		FlognHandler		; 0010100 flogn
	bra.w		flog10Handler		; 0010101 flog10
	bra.w		flog2Handler		; 0010110 flog2
	bra.w		UnsupportedHandler	; 0010111
	bra.w		FabsHandler			; 0011000 fabs
	bra.w		FcoshHandler		; 0011001 fcosh
	bra.w		FnegHandler			; 0011010 fneg
	bra.w		UnsupportedHandler	; 0011011
	bra.w		FacosHandler		; 0011100 facos
	bra.w		FcosHandler			; 0011101 fcos
	bra.w		FgetexpHandler		; 0011110 fgetexp
	bra.w		FgetmanHandler		; 0011111 fgetman
	bra.w		FdivHandler			; 0100000 fdiv
	bra.w		UnsupportedHandler	; 0100001
	bra.w		FaddHandler			; 0100010 fadd
	bra.w		FmulHandler			; 0100011 fmul
	bra.w		FsgldivHandler		; 0100100 fsgldiv
	bra.w		UnsupportedHandler	; 0100101
	bra.w		FscaleHandler		; 0100110 fscale
	bra.w		FsglmulHandler		; 0100111 fsglmul
	bra.w		FsubHandler			; 0101000 fsub
	bra.w		UnsupportedHandler	; 0101001
	bra.w		UnsupportedHandler	; 0101010
	bra.w		UnsupportedHandler	; 0101011
	bra.w		UnsupportedHandler	; 0101100
	bra.w		UnsupportedHandler	; 0101101
	bra.w		UnsupportedHandler	; 0101110
	bra.w		UnsupportedHandler	; 0101111
	bra.w		FsincosHandler		; 0110000 fsincos
	bra.w		FsincosHandler		; 0110001 fsincos
	bra.w		FsincosHandler		; 0110010 fsincos
	bra.w		FsincosHandler		; 0110011 fsincos
	bra.w		FsincosHandler		; 0110100 fsincos
	bra.w		FsincosHandler		; 0110101 fsincos
	bra.w		FsincosHandler		; 0110110 fsincos
	bra.w		FsincosHandler		; 0110111 fsincos
	bra.w		FcmpHandler			; 0111000 fcmp
	bra.w		UnsupportedHandler	; 0111001
	bra.w		FtstHandler			; 0111010 ftst
	bra.w		UnsupportedHandler	; 0111011
	bra.w		UnsupportedHandler	; 0111100
	bra.w		UnsupportedHandler	; 0111101
	bra.w		UnsupportedHandler	; 0111110
	bra.w		UnsupportedHandler	; 0111111
	bra.w		FmoveEaRegHandler	; 1000000 fsmove	
	bra.w		FssqrtHandler		; 1000001 fssqrt
	bra.w		UnsupportedHandler	; 1000010
	bra.w		UnsupportedHandler	; 1000011
	bra.w		FmoveEaRegHandler	; 1000100 fdmove
	bra.w		FdsqrtHandler		; 1000101 fdsqrt
	bra.w		UnsupportedHandler	; 1000110
	bra.w		UnsupportedHandler	; 1000111
	bra.w		UnsupportedHandler	; 1001000
	bra.w		UnsupportedHandler	; 1001001
	bra.w		UnsupportedHandler	; 1001010
	bra.w		UnsupportedHandler	; 1001011
	bra.w		UnsupportedHandler	; 1001100
	bra.w		UnsupportedHandler	; 1001101
	bra.w		UnsupportedHandler	; 1001110
	bra.w		UnsupportedHandler	; 1001111
	bra.w		UnsupportedHandler	; 1010000
	bra.w		UnsupportedHandler	; 1010001
	bra.w		UnsupportedHandler	; 1010010
	bra.w		UnsupportedHandler	; 1010011
	bra.w		UnsupportedHandler	; 1010100
	bra.w		UnsupportedHandler	; 1010101
	bra.w		UnsupportedHandler	; 1010110
	bra.w		UnsupportedHandler	; 1010111
	bra.w		FsabsHandler		; 1011000 fsabs
	bra.w		UnsupportedHandler	; 1011001
	bra.w		FsnegHandler		; 1011010 fsneg 
	bra.w		UnsupportedHandler	; 1011011
	bra.w		FdabsHandler		; 1011100 fdabs
	bra.w		UnsupportedHandler	; 1011101
	bra.w		FdnegHandler		; 1011110 fdneg
	bra.w		UnsupportedHandler	; 1011111
	bra.w		FsdivHandler		; 1100000 fsdiv
	bra.w		UnsupportedHandler	; 1100001
	bra.w		FsaddHandler		; 1100010 fsadd
	bra.w		FsmulHandler		; 1100011 fsmul
	bra.w		FddivHandler		; 1100100 fddiv
	bra.w		UnsupportedHandler	; 1100101
	bra.w		FdaddHandler		; 1100110 fdadd
	bra.w		FdmulHandler		; 1100111 fdmul
	bra.w		FssubHandler		; 1101000 fssub
	bra.w		UnsupportedHandler	; 1101001
	bra.w		UnsupportedHandler	; 1101010
	bra.w		UnsupportedHandler	; 1101011
	bra.w		FdsubHandler		; 1101100 fdsub
	bra.w		UnsupportedHandler	; 1101101
	bra.w		UnsupportedHandler	; 1101110
	bra.w		UnsupportedHandler	; 1101111
	bra.w		UnsupportedHandler	; 1110000
	bra.w		UnsupportedHandler	; 1110001
	bra.w		UnsupportedHandler	; 1110010
	bra.w		UnsupportedHandler	; 1110011
	bra.w		UnsupportedHandler	; 1110100
	bra.w		UnsupportedHandler	; 1110101
	bra.w		UnsupportedHandler	; 1110110
	bra.w		UnsupportedHandler	; 1110111
	bra.w		UnsupportedHandler	; 1111000
	bra.w		UnsupportedHandler	; 1111001
	bra.w		UnsupportedHandler	; 1111010
	bra.w		UnsupportedHandler	; 1111011
	bra.w		UnsupportedHandler	; 1111100
	bra.w		UnsupportedHandler	; 1111101
	bra.w		UnsupportedHandler	; 1111110
	bra.w		UnsupportedHandler	; 1111111

	
;
; Direct op vectors for 080 (for bypassing op and ea decoding).
;
	ifd VECTOR080
DirectOpVectors	
	cnop 		0,4
	DirectOpVectorsAligned:
	dc.l		HandleException		; 0000000 fmove
	dc.l		HandleException		; 0000001 fint
	dc.l		HandleException		; 0000010 fsinh
	dc.l		HandleException		; 0000011 fintrz
	dc.l		HandleException		; 0000100 fsqrt
	dc.l		HandleException		; 0000101
	dc.l		HandleException		; 0000110
	dc.l		HandleException		; 0000111
	dc.l		HandleException		; 0001000
	dc.l		HandleException		; 0001001 ftanh
	dc.l		HandleException		; 0001010 fatan
	dc.l		HandleException		; 0001011
	dc.l		HandleException		; 0001100 fasin
	dc.l		HandleException		; 0001101
	dc.l		HandleException		; 0001110 fsin
	dc.l		HandleException		; 0001111 ftan
	dc.l		HandleException		; 0010000 fetox
	dc.l		HandleException		; 0010001 ftwotox
	dc.l		HandleException		; 0010010 ftentox
	dc.l		HandleException		; 0010011
	dc.l		HandleException		; 0010100 flogn
	dc.l		HandleException		; 0010101 flog10
	dc.l		HandleException		; 0010110 flog2
	dc.l		HandleException		; 0010111
	dc.l		FabsHandler080		; 0011000 fabs
	dc.l		HandleException		; 0011001 fcosh
	dc.l		HandleException		; 0011010 fneg
	dc.l		HandleException		; 0011011
	dc.l		HandleException		; 0011100 facos
	dc.l		HandleException		; 0011101 fcos
	dc.l		HandleException		; 0011110 fgetexp
	dc.l		HandleException		; 0011111 fgetman
	dc.l		HandleException		; 0100000 fdiv
	dc.l		HandleException		; 0100001
	dc.l		FaddHandler080		; 0100010 fadd
	dc.l		FmulHandler080		; 0100011 fmul
	dc.l		HandleException		; 0100100 fsgldiv
	dc.l		HandleException		; 0100101
	dc.l		HandleException		; 0100110 fscale
	dc.l		FsglmulHandler080	; 0100111 fsglmul
	dc.l		FsubHandler080		; 0101000 fsub
	dc.l		HandleException		; 0101001
	dc.l		HandleException		; 0101010
	dc.l		HandleException		; 0101011
	dc.l		HandleException		; 0101100
	dc.l		HandleException		; 0101101
	dc.l		HandleException		; 0101110
	dc.l		HandleException		; 0101111
	dc.l		HandleException		; 0110000 fsincos
	dc.l		HandleException		; 0110001 fsincos
	dc.l		HandleException		; 0110010 fsincos
	dc.l		HandleException		; 0110011 fsincos
	dc.l		HandleException		; 0110100 fsincos
	dc.l		HandleException		; 0110101 fsincos
	dc.l		HandleException		; 0110110 fsincos
	dc.l		HandleException		; 0110111 fsincos
	dc.l		HandleException		; 0111000 fcmp
	dc.l		HandleException		; 0111001
	dc.l		HandleException		; 0111010 ftst
	dc.l		HandleException		; 0111011
	dc.l		HandleException		; 0111100
	dc.l		HandleException		; 0111101
	dc.l		HandleException		; 0111110
	dc.l		HandleException		; 0111111
	dc.l		HandleException		; 1000000 fsmove
	dc.l		HandleException		; 1000001 fssqrt
	dc.l		HandleException		; 1000010
	dc.l		HandleException		; 1000011
	dc.l		HandleException		; 1000100 fdmove
	dc.l		HandleException		; 1000101 fdsqrt
	dc.l		HandleException		; 1000110
	dc.l		HandleException		; 1000111
	dc.l		HandleException		; 1001000
	dc.l		HandleException		; 1001001
	dc.l		HandleException		; 1001010
	dc.l		HandleException		; 1001011
	dc.l		HandleException		; 1001100
	dc.l		HandleException		; 1001101
	dc.l		HandleException		; 1001110
	dc.l		HandleException		; 1001111
	dc.l		HandleException		; 1010000
	dc.l		HandleException		; 1010001
	dc.l		HandleException		; 1010010
	dc.l		HandleException		; 1010011
	dc.l		HandleException		; 1010100
	dc.l		HandleException		; 1010101
	dc.l		HandleException		; 1010110
	dc.l		HandleException		; 1010111
	dc.l		FsabsHandler080		; 1011000 fsabs
	dc.l		HandleException		; 1011001
	dc.l		HandleException		; 1011010 fsneg
	dc.l		HandleException		; 1011011
	dc.l		FdabsHandler080		; 1011100 fdabs
	dc.l		HandleException		; 1011101
	dc.l		HandleException		; 1011110 fdneg
	dc.l		HandleException		; 1011111
	dc.l		HandleException		; 1100000 fsdiv
	dc.l		HandleException		; 1100001
	dc.l		FsaddHandler080		; 1100010 fsadd
	dc.l		FsmulHandler080		; 1100011 fsmul
	dc.l		HandleException		; 1100100 fddiv
	dc.l		HandleException		; 1100101
	dc.l		FdaddHandler080		; 1100110 fdadd
	dc.l		FdmulHandler080		; 1100111 fdmul
	dc.l		FssubHandler080 	; 1101000 fssub
	dc.l		HandleException		; 1101001
	dc.l		HandleException		; 1101010
	dc.l		HandleException		; 1101011
	dc.l		FdsubHandler080		; 1101100 fdsub
	dc.l		HandleException		; 1101101
	dc.l		HandleException		; 1101110
	dc.l		HandleException		; 1101111
	dc.l		HandleException		; 1110000
	dc.l		HandleException		; 1110001
	dc.l		HandleException		; 1110010
	dc.l		HandleException		; 1110011
	dc.l		HandleException		; 1110100
	dc.l		HandleException		; 1110101
	dc.l		HandleException		; 1110110
	dc.l		HandleException		; 1110111
	dc.l		HandleException		; 1111000
	dc.l		HandleException		; 1111001
	dc.l		HandleException		; 1111010
	dc.l		HandleException		; 1111011
	dc.l		HandleException		; 1111100
	dc.l		HandleException		; 1111101
	dc.l		HandleException		; 1111110
	dc.l		HandleException		; 1111111
	endif


;	
;  Instruction bits 0...5 vectors.
;
OpBits0005Vectors
	bra.w		FsccHandler			; 000000 fscc dn
	bra.w		FsccHandler			; 000001 fscc dn
	bra.w		FsccHandler			; 000010 fscc dn
	bra.w		FsccHandler			; 000011 fscc dn
	bra.w		FsccHandler			; 000100 fscc dn
	bra.w		FsccHandler			; 000101 fscc dn
	bra.w		FsccHandler			; 000110 fscc dn
	bra.w		FsccHandler			; 000111 fscc dn
	bra.w		FdbccHandler		; 001000 fdbcc/cpdbcc 
	bra.w		FdbccHandler		; 001001 fdbcc/cpdbcc 
	bra.w		FdbccHandler		; 001010 fdbcc/cpdbcc 
	bra.w		FdbccHandler		; 001011 fdbcc/cpdbcc 
	bra.w		FdbccHandler		; 001100 fdbcc/cpdbcc 
	bra.w		FdbccHandler		; 001101 fdbcc/cpdbcc
	bra.w		FdbccHandler		; 001110 fdbcc/cpdbcc
	bra.w		FdbccHandler		; 001111 fdbcc/cpdbcc
	bra.w		FsccHandler			; 010000 fscc (an)
	bra.w		FsccHandler			; 010001 fscc (an) 
	bra.w		FsccHandler			; 010010 fscc (an)
	bra.w		FsccHandler			; 010011 fscc (an)
	bra.w		FsccHandler			; 010100 fscc (an)
	bra.w		FsccHandler			; 010101 fscc (an)
	bra.w		FsccHandler			; 010110 fscc (an)
	bra.w		FsccHandler			; 010111 fscc (an)
	bra.w		FsccHandler			; 011000 fscc (an)+
	bra.w		FsccHandler			; 011001 fscc (an)+
	bra.w		FsccHandler			; 011010 fscc (an)+
	bra.w		FsccHandler			; 011011 fscc (an)+
	bra.w		FsccHandler			; 011100 fscc (an)+
	bra.w		FsccHandler			; 011101 fscc (an)+
	bra.w		FsccHandler			; 011110 fscc (an)+
	bra.w		FsccHandler			; 011111 fscc (an)+
	bra.w		FsccHandler			; 100000 fscc -(an)
	bra.w		FsccHandler			; 100001 fscc -(an)
	bra.w		FsccHandler			; 100010 fscc -(an)
	bra.w		FsccHandler			; 100011 fscc -(an)
	bra.w		FsccHandler			; 100100 fscc -(an)
	bra.w		FsccHandler			; 100101 fscc -(an)
	bra.w		FsccHandler			; 100110 fscc -(an)
	bra.w		FsccHandler			; 100111 fscc -(an)
	bra.w		FsccHandler			; 101000 fscc (d16,an)
	bra.w		FsccHandler			; 101001 fscc (d16,an)
	bra.w		FsccHandler			; 101010 fscc (d16,an)
	bra.w		FsccHandler			; 101011 fscc (d16,an)
	bra.w		FsccHandler			; 101100 fscc (d16,an)
	bra.w		FsccHandler			; 101101 fscc (d16,an)
	bra.w		FsccHandler			; 101110 fscc (d16,an)
	bra.w		FsccHandler			; 101111 fscc (d16,an)
	bra.w		FsccHandler			; 110000 fscc (d,an,xn)
	bra.w		FsccHandler			; 110001 fscc (d,an,xn)
	bra.w		FsccHandler			; 110010 fscc (d,an,xn) 
	bra.w		FsccHandler			; 110011 fscc (d,an,xn)
	bra.w		FsccHandler			; 110100 fscc (d,an,xn)
	bra.w		FsccHandler			; 110101 fscc (d,an,xn)
	bra.w		FsccHandler			; 110110 fscc (d,an,xn)
	bra.w		FsccHandler			; 110111 fscc (d,an,xn)
	bra.w		FsccHandler			; 111000 fscc (xxx).w
	bra.w		FsccHandler			; 111001 fscc (xxx).l
	bra.w		UnsupportedHandler	; 111010 ftrapcc/cptrapcc word
	bra.w		UnsupportedHandler	; 111011 ftrapcc/cptrapcc long
	bra.w		UnsupportedHandler	; 111100 ftrapcc/cptrapcc null
	bra.w		UnsupportedHandler	; 111101 unused
	bra.w		UnsupportedHandler	; 111110 unused
	bra.w		UnsupportedHandler	; 111111 unused


;
; Data formats lengths.
;
FMTLENGTHS
	dc.l		$04		; 000 long
	dc.l		$04		; 001 single
	dc.l		$0c		; 010 extended
	dc.l		$0c		; 011 packed
	dc.l		$02		; 100 word
	dc.l		$08		; 101 double
	dc.l		$01		; 110 byte
	dc.l		$00		; 111 unused

	
