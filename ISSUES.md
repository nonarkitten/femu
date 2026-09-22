|  Function       | Issues     |
| :------------- | :---------- |
| fabs | optimal |
| facos | calls MathIeeeDoubTrans |
| fadd | set NOMATHLIB for best code |
| fasin | calls MathIeeeDoubTrans |
| fatan | calls MathIeeeDoubTrans |
| fbcc | optimal |
| fcmp | native, no library call (already fixed) |
| fcos | calls MathIeeeDoubTrans |
| fcosh | calls MathIeeeDoubTrans |
| fdbcc | optimal |
| fdiv | set NOMATHLIB for native, `DIV64`-based (correct, but a 64+1-iteration restoring-division loop -- see checklist `#4`'s row) extended-precision division. `fsdiv`/`fsgldiv`/FPCR-forced-single now take a separate, much faster `divu.l`-based single-precision path (checklist `#5`, ~5x faster than the extended path) -- see `ISSUES.md`'s header note and `README.md`'s `#5` row for the narrowed-operand relaxation this accepts |
| fetox | calls MathIeeeDoubTrans |
| fgetexp | may have issues |
| fgetman | doe not work at all |
| fint | set NOMATHLIB for best code |
| fintrz | set NOMATHLIB for best code |
| flog2 | calls MathIeeeDoubTrans (Log10) AND MathIeeeDoubBas (Div) |
| flog10 | calls MathIeeeDoubTrans |
| flogn | calls MathIeeeDoubTrans |
| fmove | Native internal representation landed (checklist `#4`): `RegFpn` is now the real 68881 extended layout, so `fmove.x` reg&lt;-&gt;mem is a straight copy with no conversion at all, and the old `ExtendedToDouble` rounding bug (extended 1.5 round-tripping as 1.5000000001164082) is gone along with the function itself. `fmove.d`/`.s`/`.b`/`.w`/`.l` now pay a conversion (`InternalToDouble`/`DoubleToInternal`, `src/utils/type.asm`) that `fmove.x` used to pay -- the cost relocated, as `DESIGN-04-native-extended-repr.md` predicted, not a new problem |
| fmovecr | optimal |
| fmovefpcr | optimal |
| fmovem | Native internal representation (checklist `#4`) removed the per-register `jsr` entirely for `.x` register lists -- `FMOVEMEAFPN`/`FMOVEMFPNEA` are now a straight `movem.l`, no conversion call, no more per-register cost multiplying the old rounding bug. This was the one clear, unambiguous win the whole idea was banking on (measured 1369-1457 -> 953 cycles for 4 registers) |
| fmul | set NOMATHLIB for native, hardware-`mulu.l`-based, correctly-rounded extended-precision code. `fsmul`/`fsglmul`/FPCR-forced-single now take a separate, faster single-precision path (checklist `#5`, ~19% faster than the extended path) -- see `README.md`'s `#5` row for the narrowed-operand relaxation this accepts |
| fneg | optimal |
| frestore | optimal |
| fsave | optimal |
| fscale | optimal |
| fscc | optimal |
| fsin | NOMATHLIB has been commented out? needs work |
| fsincos | calls MathIeeeDoubTrans |
| fsinh | calls MathIeeeDoubTrans |
| fsqrt | calls MathIeeeDoubTrans |
| fsub | set NOMATHLIB for best code |
| ftan | calls MathIeeeDoubTrans |
| ftanh | calls MathIeeeDoubTrans |
| ftentox | calls MathIeeeDoubTrans |
| ftst | optimal |
| ftwotox | calls MathIeeeDoubTrans |
