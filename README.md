# Software based FPU emulator

Femu is a software based fpu emulator for Amiga's without a real FPU. It was originally written by Jari Eskelinen. 
I've created a github repository to further develop and refine it -- notably, to remove dependency on the existing math libraries (breaking a weird circular dependency)
and also implement some performance improvements where possible (e.g., interpret following fpu opcodes without extra interrupt overhead, have single/double build options, relaxed IEEE enforcement, etc.).

Please be aware that software emulation is always much slower than real deal nor is compatibility perfect. YMMV, no guarantees, be happy if 
something actually works.

## Installation

Until this is fixed, if you are using OS 3.1 or 3.5, you need to copy following libraries from 
your OS 3.9 to your OS 3.1 or 3.5:

mathieeedoubbas.library
mathieeedoubtrans.library

Please backup originals first. Sorry, cannot distribute this libraries,
they are copyrighted work. Libraries from 3.1 or 3.5 won't work properly
due to bugs in them.

Extract to convenient location of your choice (e.g. C:). Run either
femustart or CPU specific femu.0x0 from CLI. Ctrl+C will stop femu and 
restore original CPU settings. It is possible to run femu from user-startup 
as well.

## Versions

femu.020 - For real 020 and 030 machines and WinUAE 3.5.0 or later (set CPU to 
68020 and enable more compatible and JIT). 

femu.040 - For real 040 machines. Does not work with WinUAE 3.5.0 properly.

femu.080 - Removed because the Vampire has an FPU now.

femustart - Detects CPU and automatically starts correct version.

## License

You can use femu for you own pleasure. There is no guarantee. If femu
corrupts your HDD or burns down your house, responsibility is yours only.
You are responsible of backing up and restoring your files. 
