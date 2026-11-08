#!/usr/bin/env python3
"""Extract the title pictures of Robot Odyssey I (v1.0/v1.1, program disk side A).

Usage: ro_title.py SIDE_A.dsk OUTDIR [--verify]

Loads the menu ($0803, $6000) and the title pictures ($6300) like the loader
does, follows the menu's title sequence (bytecode after the JSR $0803 that the
menu entry at $6000 runs) and draws its pictures with a port of the menu's
unpacker ($0A71) into the off-screen buffer at $D000.  Each wipe (opcode 1)
copies that buffer to the screen; the buffer at that moment is written as
OUTDIR/title_N.png (560x384) and OUTDIR/title_N.bin (8K hi-res page).
--verify also runs the original $0A71 on the emulator and compares the buffer
after every picture, and runs the original wipe ($0BD1) and compares hi-res
page 1 with the buffer.  Format: Docs/DiskLayout.md, "Title pictures".
"""
import sys
from pathlib import Path

from cpu6502 import CPU
import apple2kit_data  # noqa: F401  (hires, dis6502: Apple2Kit's Data/)
from hires import render, write_png
from ro_disk import Disk

# loader file table entries (track 1, $4000-$4EFF): menu, menu part 2, title pictures
MENU, MENU2, TITLE = 0x4DC4, 0x4DCA, 0x4DD0
TITLE_ADDR = 0x6300           # set by the loader ($4062) before loading the menu
DRAW_PICTURE, WIPE, INTERPRETER_LOOP = 0x0A71, 0x0BD1, 0x099A
BUFFER = 0xD000              # language card bank 2, hi-res layout of page 1 + $B000
OP_ARGS = {0: 2, 1: 0, 2: 0, 3: 3, 4: 0, 5: 0, 6: 4, 7: 0, 8: 2, 9: 2, 10: 1}


def load(disk):
    """Memory image with the menu and the title pictures loaded."""
    mem = bytearray(0x10000)
    mem[0x4000:0x5000] = disk.read(16, 16)
    for entry in (MENU, MENU2, TITLE):
        track, k, lo, hi, last, pages = mem[entry:entry + 6]
        addr = TITLE_ADDR if entry == TITLE else lo | hi << 8
        size = pages * 256 + last
        mem[addr:addr + size] = disk.read(track * 16 + k, pages + 1)[:size]
    return mem


def title_sequence(mem):
    """Pictures of each screen: the bytecode after the first JSR $0803 of the menu's entry."""
    entry = mem[0x6001] | mem[0x6002] << 8          # $6000: JMP entry
    pc = bytes(mem[entry:entry + 0x40]).index(b"\x20\x03\x08") + entry + 3
    screens, pictures = [], []
    while (op := mem[pc]) != 2:
        if op == 0:
            pictures.append(mem[pc + 1] | mem[pc + 2] << 8)
        elif op == 1:
            screens.append(pictures)
            pictures = []
        pc += 1 + OP_ARGS[op]
    return screens


def draw_picture(mem, p, cells=None):
    """Port of $0A71: unpack the picture at p into the buffer at $D000.

    The 16-byte header: +2 buffer page ($D0), +3/+4 first row/column (character
    cells of 7x8 pixels), +8/+9 and +10/+11 sizes of tile banks A and B (big
    endian).  The banks (8 bytes per tile, top line first) follow the header,
    then the stream, column by column, top to bottom:
      $00-$FA tile, $FB bank A, $FC bank B, $FF n t: tile t n times (0 = 256),
      $FE k: next column; k > 1 repeats the column's stream k times in all,
      $FD end.
    Like the original, the repeat keeps only the bank's high byte ($0BBF) and
    the tile bank ($FB/$FC) and $0BBF carry over in mem between pictures.
    """
    def byte():
        nonlocal pos
        pos += 1
        return mem[pos - 1]

    def cell(code, row, col):
        if row >= 24 or col >= 40:
            raise ValueError(f"picture ${p:04X}: cell outside the screen ({row}, {col})")
        tile = (mem[0xFB] | mem[0xFC] << 8) + code * 8
        hi = mem[p + 2] | (row >> 1 & 3)                # $0BA5: page | row bits, $28 per 8 rows
        lo = (row >> 3) * 0x28 + (row & 1) * 0x80 + col
        for line in range(8):
            mem[(hi + 4 * line) << 8 | lo] = mem[tile + line]
        if cells is not None:
            cells.add((row, col))

    bank_a = p + 16
    bank_b = bank_a + (mem[p + 8] << 8 | mem[p + 9])
    pos = bank_b + (mem[p + 10] << 8 | mem[p + 11])
    row, col = mem[p + 3], mem[p + 4]
    repeat, saved = 1, pos
    while (c := byte()) != 0xFD:
        if c == 0xFF:
            n, code = byte(), byte()
            for _ in range(n or 256):
                cell(code, row, col)
                row += 1
        elif c == 0xFE:
            row, col = mem[p + 3], col + 1
            k = byte()
            if k != 1 and k != repeat:
                repeat += 1
                pos, mem[0xFC] = saved, mem[0x0BBF]
                continue
            repeat, saved, mem[0x0BBF] = 1, pos, mem[0xFC]
        elif c >= 0xFB:
            bank = bank_b if c == 0xFC else bank_a
            mem[0xFB], mem[0xFC] = bank & 0xFF, bank >> 8
        else:
            cell(c, row, col)
            row += 1


def run_original(mem, p):
    cpu = CPU(mem)
    mem[0x3E], mem[0x3F] = p & 0xFF, p >> 8
    cpu.sp = 0xF0
    cpu.call(DRAW_PICTURE)


def run_wipe(mem):
    """Opcode 1 ($0BD1) up to its return to the interpreter loop ($099A)."""
    cpu = CPU(mem)
    cpu.sp = 0xF0
    cpu.call(WIPE, stop_at=(INTERPRETER_LOOP,))


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    if len(args) != 2:
        sys.exit(__doc__)
    verify = "--verify" in sys.argv
    mem = load(Disk(args[0]))
    original = bytearray(mem)
    out = Path(args[1])
    out.mkdir(parents=True, exist_ok=True)
    for n, pictures in enumerate(title_sequence(mem), 1):
        cells = set()
        for p in pictures:
            draw_picture(mem, p, cells)
            if verify:
                run_original(original, p)
                same = original[BUFFER:BUFFER + 0x2000] == mem[BUFFER:BUFFER + 0x2000]
                print(f"  ${p:04X}: {'identical' if same else 'DIFFERENT'} to the original $0A71")
        screen = bytes(mem[BUFFER:BUFFER + 0x2000])
        if verify:
            run_wipe(original)
            same = original[0x2000:0x4000] == screen
            print(f"  wipe: page 1 {'identical' if same else 'DIFFERENT'} to the buffer")
        (out / f"title_{n}.bin").write_bytes(screen)
        write_png(out / f"title_{n}.png", 560, 384, render(screen, 0))
        missing = 40 * 24 - len(cells)
        print(f"title_{n}: pictures {', '.join(f'${p:04X}' for p in pictures)}"
              + (f" ({missing} cells left from before)" if missing else ""))


if __name__ == "__main__":
    main()
