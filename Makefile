SRCDIR	= src
OBJDIR	= obj
BINDIR	= bin
SRCFILES = $(wildcard src/*.ASM) $(wildcard src/ops/*.ASM) $(wildcard src/utils/*.ASM)
CC = m68k-amigaos-gcc
ASM = vasmm68k_mot -Fhunk -I$(SRCDIR) 
LINK = vlink -S -s
FLAGS020 = -m68020 -DCPU020 -DSTACK020
FLAGS040 = -m68020 -DCPU040 -DSTACK040 -DSTACKEA

all: femu femustart ftest genccc gentruth

femu: femu.020 femu.020m femu.040 femu.040m 

femu.020: $(SRCFILES)
	$(ASM) $(FLAGS020) -o $(OBJDIR)/$@.o $(SRCDIR)/femu.asm 
	$(LINK) -bamigahunk -o $(BINDIR)/$@ $(OBJDIR)/$@.o 
	
femu.020m: $(SRCFILES)
	$(ASM) $(FLAGS020) -DNOMATHLIB -o $(OBJDIR)/$@.o $(SRCDIR)/femu.asm 
	$(LINK) -bamigahunk -o $(BINDIR)/$@ $(OBJDIR)/$@.o
	
femu.040: $(SRCFILES)
	$(ASM) $(FLAGS040) -o $(OBJDIR)/$@.o $(SRCDIR)/femu.asm 
	$(LINK) -bamigahunk -o $(BINDIR)/$@ $(OBJDIR)/$@.o
	
femu.040m: $(SRCFILES)
	$(ASM) $(FLAGS040) -DNOMATHLIB -o $(OBJDIR)/$@.o $(SRCDIR)/femu.asm 
	$(LINK) -bamigahunk -o $(BINDIR)/$@ $(OBJDIR)/$@.o
		
femustart: 
	$(CC) $(SRCDIR)/$@.c -o $(BINDIR)/$@
	
ftest: $(SRCFILES)
	$(ASM) -m68080 -m68881 -no-opt -o $(OBJDIR)/$@.o $(SRCDIR)/ftest.asm 
	$(LINK) -bamigahunk -o $(BINDIR)/$@ $(OBJDIR)/$@.o
	
genccc: $(SRCFILES)
	vasmm68k_mot -m68020 -m68881 -Fhunkexe $(SRCDIR)/$@.ASM -o $(BINDIR)/$@
	
gentruth: $(SRCFILES)
	vasmm68k_mot -m68020 -m68881 -Fhunkexe $(SRCDIR)/$@.ASM -o $(BINDIR)/$@
	
clean:
	delete '$(OBJDIR)/#?' '$(BINDIR)/#?'
