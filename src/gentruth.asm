;		
; Generates truth table for fbcc. Run with real FPU, result 
; are to be used with the fbcc emulation code.
;
; Truth table is made out of 16 long values. Each long value
; represents one fbsrcc flag combination and all 16 covers
; all possible fbsrcc values. Bits of long values will represent
; truth value for one individual fbcc test - predicate will indicate
; bit number and bit will indicate true or false.
;
Main
	
	; Loop thru all possible fpsrcc values
	move.l			#15,d0
	.FpCcLoop:
	
		; Set fpsrcc register
		fmove.l			fpsr,d1
		bfins			d0,d1{0:8}
		fmove.l			d1,fpsr
		
		; Initialize truth table entry to all true
		move.l			#$ffffffff,d2
		
		; Then turn individual bits off if approppriate
		fbf				.F
		bclr			#0,d2
		.F:
		
		fbeq			.Eq
		bclr			#1,d2
		.Eq:
		
		fbogt			.Ogt
		bclr			#2,d2
		.Ogt:
		
		fboge			.Oge
		bclr			#3,d2
		.Oge:
		
		fbolt			.Olt
		bclr			#4,d2
		.Olt:
		
		fbole			.Ole
		bclr			#5,d2
		.Ole:
		
		fbogl			.Ogl
		bclr			#6,d2
		.Ogl:
		
		fbor			.Or
		bclr			#7,d2
		.Or:
		
		fbun			.Un
		bclr			#8,d2
		.Un:
		
		fbueq			.Ueq
		bclr			#9,d2
		.Ueq:
		
		fbugt			.Ugt
		bclr			#10,d2
		.Ugt:
		
		fbuge			.Uge
		bclr			#11,d2
		.Uge:
		
		fbult			.Ult
		bclr			#12,d2
		.Ult:
		
		fbule			.Ule
		bclr			#13,d2
		.Ule:
		
		fbne			.Ne
		bclr			#14,d2
		.Ne:
		
		fbt				.T
		bclr			#15,d2
		.T:
		
		fbsf			.Sf
		bclr			#16,d2
		.Sf:
		
		fbseq			.Seq
		bclr			#17,d2
		.Seq:
		
		fbgt			.Gt
		bclr			#18,d2
		.Gt:
		
		fbge			.Ge
		bclr			#19,d2
		.Ge:
		
		fblt			.Lt
		bclr			#20,d2
		.Lt:
		
		fble			.Le
		bclr			#21,d2
		.Le:
		
		fbgl			.Gl
		bclr			#22,d2
		.Gl:
		
		fbgle			.Gle
		bclr			#23,d2
		.Gle:
		
		fbngle			.Ngle
		bclr			#24,d2
		.Ngle:
		
		fbngl			.Ngl
		bclr			#25,d2
		.Ngl:
		
		fbnle			.Nle
		bclr			#26,d2
		.Nle:
		
		fbnlt			.Nlt
		bclr			#27,d2
		.Nlt:
		
		fbnge			.Nge
		bclr			#28,d2
		.Nge:
		
		fbngt			.Ngt
		bclr			#29,d2
		.Ngt:
		
		fbsne			.Sne
		bclr			#30,d2
		.Sne:
		
		fbst			.St
		bclr			#31,d2
		.St:
		
		; Write entry to truth table
		move.l			d2,(TruthTable,d0.w*4)
		
	dbf			d0,.FpCcLoop
	
	; Done
	clr.w			$100
	clr.l			d0
	rts

TruthTable:
	dc.l	0 ; 0000
	dc.l	0 ; 0001
	dc.l	0 ; 0010
	dc.l	0 ; 0011
	dc.l	0 ; 0100
	dc.l	0 ; 0101
	dc.l	0 ; 0110
	dc.l	0 ; 0111	
	dc.l	0 ; 1000
	dc.l	0 ; 1001
	dc.l	0 ; 1010
	dc.l	0 ; 1011
	dc.l	0 ; 1100
	dc.l	0 ; 1101
	dc.l	0 ; 1110
	dc.l	0 ; 1111
