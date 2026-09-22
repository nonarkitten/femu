;
; Bench harness wrapper around femu.asm.
;
; femu.asm is included completely unmodified below. This file only
; prepends a tiny fixed-size symbol table (raw longword addresses) so
; the C harness can find the handful of labels it needs -- the exception
; entry point and the two library base variables -- without parsing an
; assembler listing. Because this table sits at the very start of the
; assembled image, and the harness loads the whole image at address 0
; (the same base vasm assumes when resolving femu's internal absolute
; references), the offsets below are fixed and known ahead of time.
;
; Layout (big-endian longwords, matching the harness's own reads):
;   +0  'BEN1' magic (sanity check)
;   +4  HandleException address
;   +8  RegFpn address (16 FP registers x 12 bytes, native 68881
;       extended: sign+exponent(15)+reserved word, 64-bit explicit-bit
;       mantissa -- checklist #4)
;   +12 MathIeeeDoubBasBase address (femu's own storage cell)
;   +16 MathIeeeDoubTransBase address (femu's own storage cell)
;
	dc.l	$42454e31
	dc.l	HandleException
	dc.l	RegFpn
	dc.l	MathIeeeDoubBasBase
	dc.l	MathIeeeDoubTransBase
	include	"femu.asm"
