// AppleWin's NMOS 6502 (its own cpu6502.h, cpu_general.inl and
// cpu_instructions.inl, included from an AppleWin checkout) on random single
// instructions, for cpu_check.swift to compare the MOS6502 package with.
// Build and run with cpu_check.sh.
//
// Writes: the 64K memory every case starts from, then per case
//   in:  pc u16, a x y p sp u8, the 3 instruction bytes
//   out: pc u16, a x y p sp u8, cycles u32, jammed u8, n u16, n x (address u16, value u8)
// (the bytes that differ from the start memory afterwards; little-endian).

#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <vector>

// The types and machine AppleWin's macros expect
typedef uint8_t BYTE;
typedef uint16_t WORD;
typedef int BOOL;
typedef uint32_t ULONG;
typedef unsigned int UINT;
typedef BYTE* LPBYTE;
typedef WORD* LPWORD;
#define __stdcall

enum { AF_SIGN = 0x80, AF_OVERFLOW = 0x40, AF_RESERVED = 0x20, AF_BREAK = 0x10,
       AF_DECIMAL = 0x08, AF_INTERRUPT = 0x04, AF_ZERO = 0x02, AF_CARRY = 0x01 };
enum eCpuType { CPU_UNKNOWN, CPU_6502, CPU_65C02, CPU_Z80 };
#define _6502_STACK_BEGIN 0x0100
#define _6502_STACK_END 0x01FF
#define _6502_INTERRUPT_VECTOR 0xFFFE
#define APPLE_IO_BEGIN 0xC000

struct regsrec { BYTE a, x, y, ps; WORD pc, sp; BYTE bJammed; } regs;

static BYTE memory[0x10000 + 16];           // AppleWin reads words past $FFFF unchecked
static LPBYTE mem = memory;
static LPBYTE memwrite[256];
static BYTE memdirty[256];
typedef BYTE (*iofunction)(WORD, WORD, BYTE, BYTE, ULONG);
static BYTE ioRead(WORD, WORD addr, BYTE, BYTE, ULONG) { return mem[addr]; }
static iofunction IORead[256], IOWrite[256];

static eCpuType GetActiveCpu() { return CPU_6502; }
static UINT z80_mainloop(ULONG, ULONG) { return 0; }
static bool NMI(ULONG&, BOOL&, BOOL&, BOOL&, BOOL&) { return false; }
static bool IRQ(ULONG&, BOOL&, BOOL&, BOOL&, BOOL&) { return false; }
static void CheckSynchronousInterruptSources(UINT, ULONG) {}
static void NTSC_VideoUpdateCycles(ULONG) {}
static void DoIrqProfiling(ULONG) {}
#define HEATMAP_X(address)

static void Fetch(BYTE& iOpcode, ULONG uExecutedCycles) {
    const WORD PC = regs.pc;
    iOpcode = ((PC & 0xF000) == 0xC000) ? IORead[(PC >> 4) & 0xFF](PC, PC, 0, 0, uExecutedCycles) : *(mem + PC);
    regs.pc++;
}

#include "cpu_general.inl"
#include "cpu_instructions.inl"
#define READ(addr) _READ(addr)
#define WRITE(value) _WRITE(value)
#include "cpu6502.h"

static uint32_t state = 2463534242u;
static uint32_t rnd() { state ^= state << 13; state ^= state >> 17; state ^= state << 5; return state; }

/// Memory bytes: often the edges ADC, DCP, ISC... care about.
static BYTE interestingByte() {
    static const BYTE edges[] = {0x00, 0xFF, 0x80, 0x7F, 0x01, 0x99, 0x09, 0x50};
    return rnd() % 4 == 0 ? edges[rnd() % 8] : BYTE(rnd());
}

template <typename T> static void put(FILE* f, T v) { fwrite(&v, sizeof v, 1, f); }

int main(int argc, char** argv) {
    int perOpcode = argc > 2 ? atoi(argv[2]) : 1000;
    FILE* out = fopen(argc > 1 ? argv[1] : "cpu_cases.bin", "wb");
    if (!out) { perror("output"); return 1; }
    for (int page = 0; page < 256; page++) {
        memwrite[page] = mem + page * 256;
        IORead[page] = ioRead;
        IOWrite[page] = nullptr;
    }
    std::vector<BYTE> start(0x10000);
    for (auto& b : start) b = interestingByte();
    fwrite(start.data(), 1, 0x10000, out);

    for (int opcode = 0; opcode < 256; opcode++) {
        for (int n = 0; n < perOpcode; n++) {
            memcpy(mem, start.data(), 0x10000);
            WORD pc = rnd() % 0xFFFD;
            BYTE code[3] = {BYTE(opcode), interestingByte(), interestingByte()};
            memcpy(mem + pc, code, 3);
            BYTE a = interestingByte(), x = rnd(), y = rnd(), p = BYTE(rnd()) | AF_RESERVED, sp = rnd();
            regs = {a, x, y, p, pc, WORD(0x100 | sp), 0};

            ULONG cycles = Cpu6502(1, false);

            put(out, pc); put(out, a); put(out, x); put(out, y); put(out, p); put(out, sp);
            fwrite(code, 1, 3, out);
            put(out, regs.pc); put(out, regs.a); put(out, regs.x); put(out, regs.y);
            put(out, regs.ps); put(out, BYTE(regs.sp)); put(out, uint32_t(cycles)); put(out, regs.bJammed);
            std::vector<WORD> changed;
            for (int i = 0; i < 0x10000; i++) {
                BYTE before = (i >= pc && i < pc + 3) ? code[i - pc] : start[i];
                if (mem[i] != before) changed.push_back(WORD(i));
            }
            put(out, WORD(changed.size()));
            for (WORD i : changed) { put(out, i); put(out, mem[i]); }
        }
    }
    fclose(out);
    return 0;
}
