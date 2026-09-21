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
| fdiv | set NOMATHLIB for native (slow, correct) 54-iteration division |
| fetox | calls MathIeeeDoubTrans |
| fgetexp | may have issues |
| fgetman | doe not work at all |
| fint | set NOMATHLIB for best code |
| fintrz | set NOMATHLIB for best code |
| flog2 | calls MathIeeeDoubTrans (Log10) AND MathIeeeDoubBas (Div) |
| flog10 | calls MathIeeeDoubTrans |
| flogn | calls MathIeeeDoubTrans |
| fmove | `fmove.x <ea>,FPn` (and `fmovem.x` for the same reason -- see below) rounds wrong: extended 1.5 round-trips as 1.5000000001164082, a real bug in `ExtendedToDouble`'s mantissa bit-shuffling (`src/utils/type.asm`), found by `bench/`'s fmove probe (see `DESIGN-04-native-extended-repr.md`); every other direction/format is exact. Also pays real, measured conversion overhead versus `fmove.d`, which is free today since the internal format is already double -- see the design doc for checklist `#4` on whether that's worth changing |
| fmovecr | optimal |
| fmovefpcr | optimal |
| fmovem | inherits `fmove.x`'s rounding bug above for `.x` register lists (via the same `ExtendedToDouble` call), and pays that conversion cost once per register in the list -- see `DESIGN-04-native-extended-repr.md` for measured numbers |
| fmul | set NOMATHLIB for native, hardware-mulu.l-based, correctly-rounded code |
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
