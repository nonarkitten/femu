# femu bench harness -- see BENCHMARK.md for the design and bench/README.md
# for how to run this.
#
# Builds (in order): vasm (vendored, unless already on PATH), the two femu
# flat-binary variants under test, the test-opcode blob, Musashi's
# generated opcode tables, and the harness itself.

SRC          = ../src
VASM_DIR     = vendor/vasm
MUSASHI_DIR  = vendor/musashi
BUILD        = build
GEN          = $(BUILD)/gen

CC       = gcc
CFLAGS   = -std=c99 -O2 -Wall -Wextra -I$(MUSASHI_DIR) -I$(GEN) \
           -DM68K_ILLG_HAS_CALLBACK=1

VASM = $(BUILD)/vasmm68k_mot
ASMFLAGS020  = -m68020 -DCPU020 -DSTACK020 -I$(SRC)
ASMFLAGSMOT  = -Fbin

.PHONY: all run clean vasm-tool
all: $(BUILD)/femu-bench $(BUILD)/femu020.bin $(BUILD)/femu020m.bin $(BUILD)/ops.bin

run: all
	cd $(CURDIR) && ./$(BUILD)/femu-bench

# --- vasm: prefer a system install, else build the vendored mirror ------
vasm-tool: $(VASM)
$(VASM):
	@mkdir -p $(BUILD)
	@if command -v vasmm68k_mot >/dev/null 2>&1; then \
		echo "using system vasmm68k_mot"; \
		cp "$$(command -v vasmm68k_mot)" $(VASM); \
	else \
		echo "building vendored vasm ($(VASM_DIR))"; \
		$(MAKE) -C $(VASM_DIR) CPU=m68k SYNTAX=mot; \
		cp $(VASM_DIR)/bin/vasmm68k_mot $(VASM); \
	fi

# --- femu itself, assembled flat (no vlink needed -- see BENCHMARK.md) --
$(BUILD)/femu020.bin: src/bench_wrapper.asm $(SRC)/femu.asm $(VASM)
	$(VASM) $(ASMFLAGSMOT) $(ASMFLAGS020) -o $@ src/bench_wrapper.asm

$(BUILD)/femu020m.bin: src/bench_wrapper.asm $(SRC)/femu.asm $(VASM)
	$(VASM) $(ASMFLAGSMOT) $(ASMFLAGS020) -DNOMATHLIB -o $@ src/bench_wrapper.asm

# --- the test opcodes, assembled with real FPU mnemonics ----------------
$(BUILD)/ops.bin: src/ops.asm $(VASM)
	$(VASM) $(ASMFLAGSMOT) -m68020 -m68881 -o $@ src/ops.asm

# --- Musashi: generate its opcode tables, then compile the core ---------
$(BUILD)/m68kmake: $(MUSASHI_DIR)/m68kmake.c
	@mkdir -p $(BUILD)
	$(CC) -O2 -o $@ $<

$(GEN)/m68kops.c $(GEN)/m68kops.h: $(BUILD)/m68kmake $(MUSASHI_DIR)/m68k_in.c
	@mkdir -p $(GEN)
	$(BUILD)/m68kmake $(GEN)/ $(MUSASHI_DIR)/m68k_in.c

$(BUILD)/femu-bench: src/harness.c $(GEN)/m68kops.c $(GEN)/m68kops.h \
                      $(MUSASHI_DIR)/m68kcpu.c $(MUSASHI_DIR)/m68kfpu.c \
                      $(MUSASHI_DIR)/m68kcpu.h $(MUSASHI_DIR)/m68k.h \
                      $(MUSASHI_DIR)/softfloat/softfloat.c
	@mkdir -p $(BUILD)
	$(CC) $(CFLAGS) -o $@ src/harness.c $(GEN)/m68kops.c $(MUSASHI_DIR)/m68kcpu.c \
	    $(MUSASHI_DIR)/softfloat/softfloat.c -lm

clean:
	rm -rf $(BUILD)
	$(MAKE) -C $(VASM_DIR) clean 2>/dev/null || true
