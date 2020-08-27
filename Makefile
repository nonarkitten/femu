SRCDIR	= src
OBJDIR	= obj
BINDIR	= bin
SRCFILES = $(wildcard src/*.ASM) $(wildcard src/ops/*.ASM) $(wildcard src/utils/*.ASM)
CC = gcc
ASM = vasmm68k_mot_os3 -Fhunk -I$(SRCDIR) 
LINK = vlink -S -s
FLAGS020 = -m68020 -DCPU020 -DSTACK020
FLAGS040 = -m68020 -DCPU040 -DSTACK040 -DSTACKEA
FLAGS080V2 = -m68080 -DCPU080 -DSTACK040 
FLAGS080V3 = -m68080 -m68882 -DCPU080 -DSTACK080 -DFPN080 -DFPSR080
#FLAGS080V3 = -m68080 -m68882 -DSTACK080 -DFPN080 -DFPSR080 -DVECTOR080 -DREG080 

all: femu femudebug femustart fdebug ftest genccc gentruth

femu: femu.020 femu.020m femu.040 femu.040m femu.080v2 femu.080v2m femu.080 femu.080

femudebug: femu.020d femu.040d femu.080v2d femu.080

femu.020: $(SRCFILES)
	$(ASM) $(FLAGS020) -o $(OBJDIR)/$@.o $(SRCDIR)/femu.asm 
	$(LINK) -bamigahunk -o $(BINDIR)/$@ $(OBJDIR)/$@.o 
	
femu.020d: $(SRCFILES)
	$(ASM) $(FLAGS020) -DDEBUG -o $(OBJDIR)/$@.o $(SRCDIR)/femu.asm 
	$(LINK) -bamigahunk -o $(BINDIR)/$@ $(OBJDIR)/$@.o -ldebug
	
femu.020m: $(SRCFILES)
	$(ASM) $(FLAGS020) -DNOMATHLIB -o $(OBJDIR)/$@.o $(SRCDIR)/femu.asm 
	$(LINK) -bamigahunk -o $(BINDIR)/$@ $(OBJDIR)/$@.o
	
femu.040: $(SRCFILES)
	$(ASM) $(FLAGS040) -o $(OBJDIR)/$@.o $(SRCDIR)/femu.asm 
	$(LINK) -bamigahunk -o $(BINDIR)/$@ $(OBJDIR)/$@.o
	
femu.040d: $(SRCFILES)
	$(ASM) $(FLAGS040) -DDEBUG -o $(OBJDIR)/$@.o $(SRCDIR)/femu.asm 
	$(LINK) -bamigahunk -o $(BINDIR)/$@ $(OBJDIR)/$@.o -ldebug
	
femu.040m: $(SRCFILES)
	$(ASM) $(FLAGS040) -DNOMATHLIB -o $(OBJDIR)/$@.o $(SRCDIR)/femu.asm 
	$(LINK) -bamigahunk -o $(BINDIR)/$@ $(OBJDIR)/$@.o
	
femu.080v2: $(SRCFILES)
	$(ASM) $(FLAGS080V2) -o $(OBJDIR)/$@.o $(SRCDIR)/femu.asm 
	$(LINK) -bamigahunk -o $(BINDIR)/$@ $(OBJDIR)/$@.o
	
femu.080v2d: $(SRCFILES)
	$(ASM) $(FLAGS080V2) -DDEBUG -o $(OBJDIR)/$@.o $(SRCDIR)/femu.asm 
	$(LINK) -bamigahunk -o $(BINDIR)/$@ $(OBJDIR)/$@.o -ldebug
	
femu.080v2m: $(SRCFILES)
	$(ASM) $(FLAGS080V2) -DNOMATHLIB -o $(OBJDIR)/$@.o $(SRCDIR)/femu.asm 
	$(LINK) -bamigahunk -o $(BINDIR)/$@ $(OBJDIR)/$@.o
    
femu.080: $(SRCFILES)
	$(ASM)  $(FLAGS080V3) -o $(OBJDIR)/$@.o $(SRCDIR)/femu.asm 
	$(LINK) -bamigahunk -o $(BINDIR)/$@ $(OBJDIR)/$@.o
	
femu.080: $(SRCFILES)
	$(ASM) $(FLAGS080V3) -DDEBUG -o $(OBJDIR)/$@.o $(SRCDIR)/femu.asm 
	$(LINK) -bamigahunk -o $(BINDIR)/$@ $(OBJDIR)/$@.o -ldebug
	
femu.080: $(SRCFILES)
	$(ASM) $(FLAGS080V3) -DNOMATHLIB -o $(OBJDIR)/$@.o $(SRCDIR)/femu.asm
	$(LINK) -bamigahunk -o $(BINDIR)/$@ $(OBJDIR)/$@.o

# 080 version (quick tables) but no hard FP in emulator code (and no hard FPSR)
# Bax: Had to comment this out, take a look of FLAGS080, I would like to replace these flags with opt on flags instead of opt off
#femu.080v3mnh: $(SRCFILES)
#	$(ASM) -m68080 -m68882 $(FLAGS080) -DNOMATHLIB -DNOHARDFP -o $(OBJDIR)/$@.o $(SRCDIR)/femu.asm
#	$(LINK) -bamigahunk -o $(BINDIR)/$@ $(OBJDIR)/$@.o
	
femustart: 
	$(CC) $(SRCDIR)/$@.c -o $(BINDIR)/$@
	
fdebug: $(SRCFILES)
	$(ASM) -m68080 -m68881 -no-opt -o $(OBJDIR)/$@.o $(SRCDIR)/fdebug.asm 
	$(LINK) -bamigahunk -o $(BINDIR)/$@ $(OBJDIR)/$@.o
	
ftest: $(SRCFILES)
	$(ASM) -m68080 -m68881 -no-opt -o $(OBJDIR)/$@.o $(SRCDIR)/ftest.asm 
	$(LINK) -bamigahunk -o $(BINDIR)/$@ $(OBJDIR)/$@.o
	
genccc: $(SRCFILES)
	vasmm68k_mot -m68020 -m68881 -Fhunkexe $(SRCDIR)/$@.ASM -o $(BINDIR)/$@
	
gentruth: $(SRCFILES)
	vasmm68k_mot -m68020 -m68881 -Fhunkexe $(SRCDIR)/$@.ASM -o $(BINDIR)/$@
	
clean:
	delete '$(OBJDIR)/#?' '$(BINDIR)/#?'
