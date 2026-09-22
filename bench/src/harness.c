/*
 * femu bench harness -- checklist item #0 (see ../../README.md).
 *
 * Runs femu's real, assembled HandleException through a headless
 * Musashi 68020 core (no AmigaOS, no ROM) and reports, per opcode,
 * the exact number of 68k cycles the trap took and whether the
 * result matches a host-computed reference value. See ../../BENCHMARK.md
 * for the design this implements.
 *
 * femu's own mathieeedoubbas.library / mathieeedoubtrans.library calls
 * are intercepted (not executed -- those libraries aren't present) and
 * answered with the equivalent host libm call, so the ops that still
 * go through them can be measured and checked for correctness even
 * though we don't have AmigaOS to actually load them. Cycles spent
 * *inside* an intercepted call are not counted (there's no real 68k
 * code to count cycles for) -- such rows are marked "(stub)" in the
 * report so they're never confused with a fully-native measurement.
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <math.h>
#include "m68k.h"

/* ---- memory map (see BENCHMARK.md) --------------------------------- */
#define MEM_SIZE        0x00100000u
#define TEST_CODE       0x00010000u   /* where the F-line op under test lives */
#define EA_BUF          0x00060000u   /* scratch memory operand for fmove/fmovem probes */
#define BAS_LIB_BASE    0x00080000u   /* fake mathieeedoubbas.library base */
#define TRANS_LIB_BASE  0x00081000u   /* fake mathieeedoubtrans.library base */
#define VEC_BASE        0x000F0000u   /* synthetic exception vector table (VBR) */
#define SSP_INIT        0x000EFF00u   /* initial supervisor stack pointer */
#define STUB_ILLEGAL    0x4AFCu       /* ILLEGAL opcode, used to mark stub slots */
#define LIB_REGION_SIZE 0x100u        /* bytes of ILLEGAL-filled region per library */

static uint8_t mem[MEM_SIZE];

static void oob(const char *what, unsigned addr)
{
	fprintf(stderr, "bench: %s out of bounds @ %08x (pc=%08x)\n",
	        what, addr, m68k_get_reg(NULL, M68K_REG_PPC));
	exit(1);
}

/* ---- Musashi memory glue -------------------------------------------- */
unsigned int m68k_read_memory_8(unsigned int address)
{
	if (address >= MEM_SIZE) oob("read8", address);
	return mem[address];
}
unsigned int m68k_read_memory_16(unsigned int address)
{
	if (address + 1 >= MEM_SIZE) oob("read16", address);
	return (mem[address] << 8) | mem[address + 1];
}
unsigned int m68k_read_memory_32(unsigned int address)
{
	if (address + 3 >= MEM_SIZE) oob("read32", address);
	return (mem[address] << 24) | (mem[address + 1] << 16) |
	       (mem[address + 2] << 8) | mem[address + 3];
}
void m68k_write_memory_8(unsigned int address, unsigned int value)
{
	if (address >= MEM_SIZE) oob("write8", address);
	mem[address] = (uint8_t)value;
}
void m68k_write_memory_16(unsigned int address, unsigned int value)
{
	if (address + 1 >= MEM_SIZE) oob("write16", address);
	mem[address] = (uint8_t)(value >> 8);
	mem[address + 1] = (uint8_t)value;
}
void m68k_write_memory_32(unsigned int address, unsigned int value)
{
	if (address + 3 >= MEM_SIZE) oob("write32", address);
	mem[address] = (uint8_t)(value >> 24);
	mem[address + 1] = (uint8_t)(value >> 16);
	mem[address + 2] = (uint8_t)(value >> 8);
	mem[address + 3] = (uint8_t)value;
}
void m68k_write_memory_32_pd(unsigned int address, unsigned int value)
{
	m68k_write_memory_32(address, value);
}

static void wr_long(unsigned addr, unsigned v) { m68k_write_memory_32(addr, v); }
static unsigned rd_long(unsigned addr) { return m68k_read_memory_32(addr); }

/* ---- double <-> register pair ---------------------------------------- */
static double get_double(unsigned hi, unsigned lo)
{
	uint64_t bits = ((uint64_t)hi << 32) | (uint32_t)lo;
	double v;
	memcpy(&v, &bits, 8);
	return v;
}
static void put_double(double v, unsigned *hi, unsigned *lo)
{
	uint64_t bits;
	memcpy(&bits, &v, 8);
	*hi = (unsigned)(bits >> 32);
	*lo = (unsigned)bits;
}
static double mem_double(unsigned addr) { return get_double(rd_long(addr), rd_long(addr + 4)); }
static void mem_put_double(unsigned addr, double v)
{
	unsigned hi, lo;
	put_double(v, &hi, &lo);
	wr_long(addr, hi);
	wr_long(addr + 4, lo);
}

/* Motorola 96-bit ("extended") memory format: word0 = sign(1)+exp(15,
 * bias 16383), word1 = reserved (0), word2:word3 = 64-bit mantissa with
 * an explicit (not hidden) integer bit at bit 63. This is now femu's
 * own internal RegFpn layout too (checklist #4 -- see
 * src/utils/type.asm's InternalToDouble/DoubleToInternal), so this is
 * used both to poke/peek FP registers directly and to set up fmove.x
 * memory operands.
 */
static void mem_put_extended(unsigned addr, double v)
{
	uint64_t bits, mant;
	unsigned sign, exp, biased_ext;
	memcpy(&bits, &v, 8);
	sign = (unsigned)(bits >> 63);
	exp = (unsigned)((bits >> 52) & 0x7ff);
	if (exp == 0) { biased_ext = 0; mant = 0; }
	else if (exp == 0x7ff) {
		/* Inf/NaN: extended's exponent-all-ones pattern, not the affine
		 * rebias below (which would land on some ordinary finite huge
		 * value instead -- these need their own case, same as
		 * DoubleToInternal in src/utils/type.asm). Infinity's mantissa
		 * is the explicit-integer-bit-only pattern; any other nonzero
		 * fraction stays a NaN. */
		biased_ext = 0x7fff;
		mant = (bits & ((1ULL << 52) - 1)) ? ((1ULL << 63) | ~0ULL) : (1ULL << 63);
	}
	else {
		biased_ext = exp - 1023 + 16383;
		mant = (1ULL << 63) | ((bits & ((1ULL << 52) - 1)) << 11);
	}
	wr_long(addr, (sign << 31) | (biased_ext << 16));
	wr_long(addr + 4, (unsigned)(mant >> 32));
	wr_long(addr + 8, (unsigned)mant);
}
static double mem_get_extended(unsigned addr)
{
	unsigned word0 = rd_long(addr), mhi = rd_long(addr + 4), mlo = rd_long(addr + 8);
	unsigned sign = word0 >> 31, biased_ext = (word0 >> 16) & 0x7fff;
	uint64_t mant = ((uint64_t)mhi << 32) | mlo, bits;
	double v;
	if (biased_ext == 0 && mant == 0) { v = 0.0; if (sign) v = -v; return v; }
	if (biased_ext == 0x7fff) {
		/* Inf/NaN -- see mem_put_extended */
		v = (mant == (1ULL << 63)) ? INFINITY : NAN;
		if (sign) v = -v;
		return v;
	}
	{
		/* Round to nearest, ties to even, on the 11 fraction bits being
		 * dropped -- matching src/utils/type.asm's InternalToDouble.
		 * femu's own native fadd/fmul/fdiv compute directly in extended
		 * precision and never call that conversion themselves (only
		 * fmove.d/transcendentals/etc. do), so this harness-side
		 * narrowing is the only place truncation-vs-rounding matters
		 * for reading their results back as a double; without this a
		 * correctly-computed extended result could read back 1 ULP off
		 * from the double reference purely from this readback step.
		 */
		uint64_t frac63 = mant & ~(1ULL << 63);
		uint64_t frac52 = frac63 >> 11;
		unsigned round_bit = (unsigned)((frac63 >> 10) & 1);
		unsigned sticky = (frac63 & 0x3ff) != 0;
		if (round_bit && (sticky || (frac52 & 1))) frac52++;
		bits = ((uint64_t)sign << 63) |
		       (((uint64_t)(biased_ext - 16383 + 1023) << 52) + frac52);
	}
	memcpy(&v, &bits, 8);
	return v;
}

/* ---- fake mathieeedoubbas.library / mathieeedoubtrans.library ------- *
 * Offsets copied verbatim from src/utils/constants.asm -- femu defines
 * these itself (no external NDK headers involved), so there is nothing
 * to keep in sync except that file and this table.
 */
static int lib_call(unsigned base_is_trans, int offset)
{
	unsigned d0 = m68k_get_reg(NULL, M68K_REG_D0);
	unsigned d1 = m68k_get_reg(NULL, M68K_REG_D1);
	unsigned d2 = m68k_get_reg(NULL, M68K_REG_D2);
	unsigned d3 = m68k_get_reg(NULL, M68K_REG_D3);
	double a = get_double(d0, d1);
	double b = get_double(d2, d3);
	double r;
	unsigned rhi, rlo;

	if (!base_is_trans) {
		switch (offset) {
		case -0x36: r = fabs(a); break;                 /* Abs */
		case -0x42: r = a + b; break;                    /* Add */
		case -0x60: r = ceil(a); break;                   /* Ceil */
		case -0x2a: m68k_set_reg(M68K_REG_D0, a == b ? 0 : (a < b ? -1 : 1)); return 1; /* Cmp */
		case -0x54: r = a / b; break;                     /* Div */
		case -0x1e: m68k_set_reg(M68K_REG_D0, (unsigned)(int)(a)); return 1; /* Fix (trunc) */
		case -0x5a: r = floor(a); break;                   /* Floor */
		case -0x24: r = (double)(int)d0; break;             /* Flt (long->double) */
		case -0x4e: r = a * b; break;                        /* Mul */
		case -0x3c: r = -a; break;                            /* Neg */
		case -0x48: r = a - b; break;                          /* Sub */
		case -0x30: m68k_set_reg(M68K_REG_D0, a == 0 ? 0 : (a < 0 ? -1 : 1)); return 1; /* Tst */
		default: return 0;
		}
	} else {
		switch (offset) {
		case -0x78: r = acos(a); break;   /* Acos */
		case -0x72: r = asin(a); break;   /* Asin */
		case -0x1e: r = atan(a); break;   /* Atan */
		case -0x2a: r = cos(a); break;    /* Cos */
		case -0x42: r = cosh(a); break;   /* Cosh */
		case -0x4e: r = exp(a); break;    /* Exp (fetox) */
		case -0x6c: {                     /* Fieeee (single->double) */
			float f; memcpy(&f, &d0, 4); r = (double)f; break;
		}
		case -0x54: r = log(a); break;    /* Log (flogn) */
		case -0x7e: r = log10(a); break;  /* Log10 */
		case -0x5a: r = pow(a, b); break; /* Pow (ftwotox/ftentox) */
		case -0x24: r = sin(a); break;    /* Sin */
		case -0x36:                       /* Sincos: d0:d1=sin, d2:d3=cos */
			put_double(sin(a), &rhi, &rlo);
			m68k_set_reg(M68K_REG_D0, rhi); m68k_set_reg(M68K_REG_D1, rlo);
			put_double(cos(a), &rhi, &rlo);
			m68k_set_reg(M68K_REG_D2, rhi); m68k_set_reg(M68K_REG_D3, rlo);
			return 1;
		case -0x3c: r = sinh(a); break;   /* Sinh */
		case -0x60: r = sqrt(a); break;   /* Sqrt */
		case -0x30: r = tan(a); break;    /* Tan */
		case -0x48: r = tanh(a); break;   /* Tanh */
		case -0x66: {                     /* Tieee (double->single) */
			float f = (float)a; unsigned bits; memcpy(&bits, &f, 4);
			m68k_set_reg(M68K_REG_D0, bits); return 1;
		}
		default: return 0;
		}
	}
	put_double(r, &rhi, &rlo);
	m68k_set_reg(M68K_REG_D0, rhi);
	m68k_set_reg(M68K_REG_D1, rlo);
	return 1;
}

static int stub_hit; /* set by illg_stub when a vector's cycles included a stub call */

static int illg_stub(int opcode)
{
	unsigned pc, sp, ret;
	int handled;

	if (opcode != STUB_ILLEGAL) return 0;
	pc = m68k_get_reg(NULL, M68K_REG_PPC);

	if (pc >= BAS_LIB_BASE - LIB_REGION_SIZE && pc < BAS_LIB_BASE)
		handled = lib_call(0, (int)pc - (int)BAS_LIB_BASE);
	else if (pc >= TRANS_LIB_BASE - LIB_REGION_SIZE && pc < TRANS_LIB_BASE)
		handled = lib_call(1, (int)pc - (int)TRANS_LIB_BASE);
	else
		return 0;

	if (!handled) return 0;
	stub_hit = 1;

	/* We were reached via jsr: (a7) holds the return address. */
	sp = m68k_get_reg(NULL, M68K_REG_A7);
	ret = rd_long(sp);
	m68k_set_reg(M68K_REG_A7, sp + 4);
	m68k_set_reg(M68K_REG_PC, ret);
	return 1;
}

/* ---- test image loading ---------------------------------------------- */
struct image {
	unsigned handle_exception, reg_fpn, bas_base_var, trans_base_var;
};

static void load_binary(const char *path, unsigned base, size_t *out_size)
{
	FILE *f = fopen(path, "rb");
	size_t n;
	if (!f) { fprintf(stderr, "bench: cannot open %s\n", path); exit(1); }
	n = fread(mem + base, 1, MEM_SIZE - base, f);
	fclose(f);
	if (out_size) *out_size = n;
}

static void parse_image_header(struct image *img)
{
	if (rd_long(0) != 0x42454e31u) {
		fprintf(stderr, "bench: bad magic in femu image (wrapper/harness out of sync?)\n");
		exit(1);
	}
	img->handle_exception = rd_long(4);
	img->reg_fpn = rd_long(8);
	img->bas_base_var = rd_long(12);
	img->trans_base_var = rd_long(16);
}

static void fill_illegal(unsigned base, unsigned size)
{
	unsigned a;
	for (a = base - size; a < base; a += 2)
		m68k_write_memory_16(a, STUB_ILLEGAL);
}

/* ---- golden vectors ---------------------------------------------------- */
struct vector {
	char op[16];
	double a, b;
	int has_b;
};

static int load_vectors(const char *path, struct vector *v, int max)
{
	FILE *f = fopen(path, "rb");
	char line[256];
	int n = 0;
	if (!f) { fprintf(stderr, "bench: cannot open %s\n", path); exit(1); }
	while (fgets(line, sizeof line, f) && n < max) {
		char opbuf[16], abuf[64], bbuf[64];
		if (line[0] == '#' || line[0] == '\n') continue;
		if (sscanf(line, "%15s %63s %63s", opbuf, abuf, bbuf) != 3) continue;
		strcpy(v[n].op, opbuf);
		v[n].a = atof(abuf);
		if (strcmp(bbuf, "-") == 0) { v[n].b = 0; v[n].has_b = 0; }
		else { v[n].b = atof(bbuf); v[n].has_b = 1; }
		n++;
	}
	fclose(f);
	return n;
}

static double reference(const char *op, double a, double b)
{
	if (!strcmp(op, "fadd")) return a + b;
	if (!strcmp(op, "fsub")) return a - b;
	if (!strcmp(op, "fmul")) return a * b;
	if (!strcmp(op, "fdiv")) return a / b;
	if (!strcmp(op, "fabs")) return fabs(a);
	if (!strcmp(op, "fneg")) return -a;
	if (!strcmp(op, "fint")) return rint(a);   /* nearest, ties handled by host FE rules */
	if (!strcmp(op, "fintrz")) return trunc(a);
	if (!strcmp(op, "fsqrt")) return sqrt(a);
	if (!strcmp(op, "facos")) return acos(a);
	if (!strcmp(op, "fasin")) return asin(a);
	if (!strcmp(op, "fatan")) return atan(a);
	if (!strcmp(op, "fcos")) return cos(a);
	if (!strcmp(op, "fcosh")) return cosh(a);
	if (!strcmp(op, "fetox")) return exp(a);
	if (!strcmp(op, "ftentox")) return pow(10.0, a);
	if (!strcmp(op, "ftwotox")) return pow(2.0, a);
	if (!strcmp(op, "flog2")) return log2(a);
	if (!strcmp(op, "flog10")) return log10(a);
	if (!strcmp(op, "flogn")) return log(a);
	if (!strcmp(op, "fsin")) return sin(a);
	if (!strcmp(op, "fsinh")) return sinh(a);
	if (!strcmp(op, "ftan")) return tan(a);
	if (!strcmp(op, "ftanh")) return tanh(a);
	fprintf(stderr, "bench: no reference implementation for '%s'\n", op);
	exit(1);
}

#define MAX_STEPS 500000

/* Runs one 4-byte opcode already placed at TEST_CODE+offset and returns
 * cycles taken, or -1 on timeout. Registers/memory must already be set
 * up by the caller; this only resets the CPU and (re)installs the
 * vector table/library bases, same as the main vector loop.
 */
static long run_one_opcode(const struct image *img, unsigned offset, int *done_out)
{
	unsigned test_pc = TEST_CODE + offset, resume_pc = test_pc + 4;
	long total_cycles = 0;
	int step;

	m68k_pulse_reset();
	m68k_set_reg(M68K_REG_VBR, VEC_BASE);
	wr_long(VEC_BASE + 0x2c, img->handle_exception);
	m68k_set_reg(M68K_REG_A7, SSP_INIT);
	m68k_set_reg(M68K_REG_SR, 0x2700);
	wr_long(img->bas_base_var, BAS_LIB_BASE);
	wr_long(img->trans_base_var, TRANS_LIB_BASE);
	m68k_set_reg(M68K_REG_A0, EA_BUF);
	m68k_set_reg(M68K_REG_PC, test_pc);

	stub_hit = 0;
	for (step = 0; step < MAX_STEPS; step++) {
		total_cycles += m68k_execute(1);
		if (m68k_get_reg(NULL, M68K_REG_PC) == resume_pc &&
		    m68k_get_reg(NULL, M68K_REG_A7) == SSP_INIT) {
			*done_out = 1;
			return total_cycles;
		}
	}
	*done_out = 0;
	return total_cycles;
}

/* Checklist item #4's post-implementation probe: RegFpn is now the
 * 96-bit extended layout itself, so fmove.x reg<->mem is a straight
 * copy (both sides mem_put_extended/mem_get_extended at the register's
 * own address) while fmove.d reg<->mem now pays the conversion that
 * fmove.x used to pay (mem_put_double/mem_double against EA_BUF, an
 * ordinary 8-byte double memory operand -- fmove.d's own memory format
 * is unchanged, only the internal register format moved). Opcodes come
 * from fmove_probe.asm, in this fixed order.
 */
static void run_fmove_probe(const struct image *img)
{
	static const char *names[6] = {
		"fmove.x (a0),fp0", "fmove.x fp0,(a0)",
		"fmove.d (a0),fp0", "fmove.d fp0,(a0)",
		"fmovem.x (a0),fp0-fp3", "fmovem.x fp0-fp3,(a0)",
	};
	int i, done;
	long cycles;
	double got;

	printf("\n=== fmove/fmovem memory-operand probe (checklist #4) ===\n");
	printf("%-24s %14s %8s  %s\n", "op", "cycles", "ok", "note");

	for (i = 0; i < 6; i++) {
		switch (i) {
		case 0: /* fmove.x (a0),fp0 */
			mem_put_extended(EA_BUF, 1.5);
			break;
		case 1: /* fmove.x fp0,(a0) */
			mem_put_extended(img->reg_fpn + 0, 1.5);
			memset(mem + EA_BUF, 0, 12);
			break;
		case 2: /* fmove.d (a0),fp0 */
			mem_put_double(EA_BUF, 1.5);
			break;
		case 3: /* fmove.d fp0,(a0) */
			mem_put_extended(img->reg_fpn + 0, 1.5);
			wr_long(EA_BUF, 0); wr_long(EA_BUF + 4, 0);
			break;
		case 4: /* fmovem.x (a0),fp0-fp3: four distinct extended values */
			mem_put_extended(EA_BUF + 0, 1.5);
			mem_put_extended(EA_BUF + 12, 2.5);
			mem_put_extended(EA_BUF + 24, 3.5);
			mem_put_extended(EA_BUF + 36, 4.5);
			break;
		case 5: /* fmovem.x fp0-fp3,(a0) */
			mem_put_extended(img->reg_fpn + 0, 1.5);
			mem_put_extended(img->reg_fpn + 12, 2.5);
			mem_put_extended(img->reg_fpn + 24, 3.5);
			mem_put_extended(img->reg_fpn + 36, 4.5);
			memset(mem + EA_BUF, 0, 48);
			break;
		}

		cycles = run_one_opcode(img, (unsigned)i * 4, &done);
		if (!done) {
			printf("%-24s %14s %8s  TIMEOUT after %d steps%s\n",
			       names[i], "-", "-", MAX_STEPS, stub_hit ? " (stub)" : "");
			continue;
		}

		switch (i) {
		case 0: got = mem_get_extended(img->reg_fpn + 0);
			printf("%-24s %14ld %8s  got %.17g, want 1.5\n", names[i], cycles,
			       got == 1.5 ? "ok" : "WRONG", got);
			break;
		case 1: got = mem_get_extended(EA_BUF);
			printf("%-24s %14ld %8s  got %.17g, want 1.5\n", names[i], cycles,
			       got == 1.5 ? "ok" : "WRONG", got);
			break;
		case 2: got = mem_get_extended(img->reg_fpn + 0);
			printf("%-24s %14ld %8s  got %.17g, want 1.5\n", names[i], cycles,
			       got == 1.5 ? "ok" : "WRONG", got);
			break;
		case 3: got = mem_double(EA_BUF);
			printf("%-24s %14ld %8s  got %.17g, want 1.5\n", names[i], cycles,
			       got == 1.5 ? "ok" : "WRONG", got);
			break;
		case 4: {
			double g0 = mem_get_extended(img->reg_fpn + 0), g1 = mem_get_extended(img->reg_fpn + 12),
			       g2 = mem_get_extended(img->reg_fpn + 24), g3 = mem_get_extended(img->reg_fpn + 36);
			int ok = (g0 == 1.5 && g1 == 2.5 && g2 == 3.5 && g3 == 4.5);
			printf("%-24s %14ld %8s  fp0-fp3 got %.3g,%.3g,%.3g,%.3g want 1.5,2.5,3.5,4.5\n",
			       names[i], cycles, ok ? "ok" : "WRONG", g0, g1, g2, g3);
			break;
		}
		case 5: {
			double g0 = mem_get_extended(EA_BUF + 0), g1 = mem_get_extended(EA_BUF + 12),
			       g2 = mem_get_extended(EA_BUF + 24), g3 = mem_get_extended(EA_BUF + 36);
			int ok = (g0 == 1.5 && g1 == 2.5 && g2 == 3.5 && g3 == 4.5);
			printf("%-24s %14ld %8s  mem got %.3g,%.3g,%.3g,%.3g want 1.5,2.5,3.5,4.5\n",
			       names[i], cycles, ok ? "ok" : "WRONG", g0, g1, g2, g3);
			break;
		}
		}
	}
}

int main(int argc, char **argv)
{
	const char *variant_paths[2] = { "build/femu020.bin", "build/femu020m.bin" };
	const char *variant_names[2] = { "femu.020 (library)", "femu.020m (NOMATHLIB)" };
	unsigned char ops[64 * 4];
	struct vector vecs[64];
	int nvec, vi, variant;
	size_t ops_size;
	FILE *opsf;

	(void)argc; (void)argv;

	opsf = fopen("build/ops.bin", "rb");
	if (!opsf) { fprintf(stderr, "bench: build/ops.bin missing -- run make first\n"); return 1; }
	ops_size = fread(ops, 1, sizeof ops, opsf);
	if (ops_size == 0 || (ops_size % 4) != 0) {
		fprintf(stderr, "bench: build/ops.bin has an unexpected size (%zu bytes, not a multiple of 4)\n", ops_size);
		return 1;
	}
	fclose(opsf);

	nvec = load_vectors("vectors/ops.txt", vecs, 64);
	if (nvec != (int)(ops_size / 4)) {
		fprintf(stderr, "bench: vectors/ops.txt has %d rows but src/ops.asm has %zu -- "
		                "the two files must be kept in lockstep\n", nvec, ops_size / 4);
		return 1;
	}

	m68k_init();
	m68k_set_cpu_type(M68K_CPU_TYPE_68020);
	m68k_set_illg_instr_callback(illg_stub);

	for (variant = 0; variant < 2; variant++) {
		struct image img;
		size_t fsize = 0;

		memset(mem, 0, MEM_SIZE);
		load_binary(variant_paths[variant], 0, &fsize);
		if (fsize == 0) {
			fprintf(stderr, "bench: %s missing or empty -- run make first\n", variant_paths[variant]);
			return 1;
		}
		parse_image_header(&img);
		fill_illegal(BAS_LIB_BASE, LIB_REGION_SIZE);
		fill_illegal(TRANS_LIB_BASE, LIB_REGION_SIZE);
		memcpy(mem + TEST_CODE, ops, ops_size);

		printf("\n=== %s ===\n", variant_names[variant]);
		printf("%-10s %14s %10s  %s\n", "op", "cycles", "match", "note");

		for (vi = 0; vi < nvec; vi++) {
			unsigned test_pc = TEST_CODE + vi * 4;
			unsigned resume_pc = test_pc + 4;
			long total_cycles = 0;
			int step, done = 0;
			double expected, actual;

			m68k_pulse_reset();
			m68k_set_reg(M68K_REG_VBR, VEC_BASE);
			wr_long(VEC_BASE + 0x2c, img.handle_exception);
			m68k_set_reg(M68K_REG_A7, SSP_INIT);
			m68k_set_reg(M68K_REG_SR, 0x2700);
			wr_long(img.bas_base_var, BAS_LIB_BASE);
			wr_long(img.trans_base_var, TRANS_LIB_BASE);
			mem_put_extended(img.reg_fpn + 0, vecs[vi].a);
			mem_put_extended(img.reg_fpn + 12, vecs[vi].has_b ? vecs[vi].b : 0.0);
			m68k_set_reg(M68K_REG_PC, test_pc);

			stub_hit = 0;
			for (step = 0; step < MAX_STEPS; step++) {
				total_cycles += m68k_execute(1);
				if (m68k_get_reg(NULL, M68K_REG_PC) == resume_pc &&
				    m68k_get_reg(NULL, M68K_REG_A7) == SSP_INIT) {
					done = 1;
					break;
				}
			}

			expected = reference(vecs[vi].op, vecs[vi].a, vecs[vi].b);
			actual = mem_get_extended(img.reg_fpn + 0);

			if (!done) {
				printf("%-10s %14s %10s  TIMEOUT after %d steps\n",
				       vecs[vi].op, "-", "-", MAX_STEPS);
				continue;
			}

			printf("%-10s %14ld %10s  %.17g vs %.17g%s\n",
			       vecs[vi].op, total_cycles,
			       (actual == expected) ? "MATCH" : "DIFFER",
			       actual, expected,
			       stub_hit ? " (stub)" : "");
		}
	}

	/* fmove/fmovem memory-operand probe for checklist #4's design pass.
	 * NOMATHLIB doesn't affect these paths (no library calls either
	 * way -- see the design doc), so the library build is enough.
	 */
	{
		struct image img;
		unsigned char probe_ops[6 * 4];
		size_t fsize = 0, probe_size;
		FILE *pf;

		pf = fopen("build/fmove_probe.bin", "rb");
		if (!pf) { fprintf(stderr, "bench: build/fmove_probe.bin missing -- run make first\n"); return 1; }
		probe_size = fread(probe_ops, 1, sizeof probe_ops, pf);
		fclose(pf);
		if (probe_size != sizeof probe_ops) {
			fprintf(stderr, "bench: build/fmove_probe.bin has the wrong size (%zu bytes, expected %zu)\n",
			        probe_size, sizeof probe_ops);
			return 1;
		}

		memset(mem, 0, MEM_SIZE);
		load_binary(variant_paths[0], 0, &fsize);
		parse_image_header(&img);
		fill_illegal(BAS_LIB_BASE, LIB_REGION_SIZE);
		fill_illegal(TRANS_LIB_BASE, LIB_REGION_SIZE);
		memcpy(mem + TEST_CODE, probe_ops, sizeof probe_ops);

		run_fmove_probe(&img);
	}

	return 0;
}
