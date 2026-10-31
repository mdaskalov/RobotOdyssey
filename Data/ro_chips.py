#!/usr/bin/env python3
"""Robot Odyssey (Apple II) chips: find them and disassemble them.

The Apple II keeps its 8 chips in the PC version's CHP format, so
ro_chip_disasm.py reads them unchanged: chip n at $D000 + $400n
(chips 0-3 in language card bank 1, 4-7 at $E000-$EFFF), 8 pin bytes, then the
bytecode. The chip table at $F008 + 8n holds the pin directions (0 = unused,
1 = in, 2 = out; pins stored 1-4, 8-5) like a CSV file's PIN table.
See Docs/Engine.md ("Chips").

Usage:
    ro_chips.py SIDE_A.dsk SIDE_B.dsk   chips the world loaders set up (Level 1, Lab Tutorial)
    ro_chips.py STATE.yaml              chips of a Mariani/AppleWin save state
    ro_chips.py STORAGE.dsk             chips of every saved game on a storage diskette
"""
import sys

import ro_chip_disasm as disasm
from aws_state import parse_state
from ro_disk import Disk

NUM_CHIPS = 8
CHIP_SIZE = 0x400
TABLE = 0xF008
EMPTY_CHIP = bytes(8) + bytes([0x07, 0xFF, 0xFF, 0xFF])     # CLEAR_CHIPS $4D13

# The loaders' chip set-up (GameCatalog.swift, Docs/DiskLayout.md): side,
# [(page, address, length)], {table address: bytes}. All other chips are cleared.
SETUPS = [
    ("Level 1 (levels 2-5 keep its chips)", 0,
     [(167, 0xD000, 0x1AA), (165, 0xD400, 0x183)],
     {0xF008: bytes([1, 1, 2, 2, 2, 2, 2, 2, 2, 1, 2, 1, 1, 2, 1, 2])}),
    ("Innovation Lab Tutorial", 1,
     [(165, 0xD800, 0x183), (167, 0xD000, 19)],
     {0xF008: bytes([2, 0, 0, 0, 0, 0, 0, 0]), 0xF018: bytes([2, 1, 2, 1, 1, 2, 1, 2])}),
]


def chip_address(n):
    return 0xD000 + CHIP_SIZE * n


def empty_chips():
    """$D000-$EFFF (bank 1 at $D000) with every chip cleared."""
    lc = bytearray(2 * 0x1000)
    for n in range(NUM_CHIPS):
        lc[n * CHIP_SIZE:n * CHIP_SIZE + len(EMPTY_CHIP)] = EMPTY_CHIP
    return lc


def disassemble(n, lc, table):
    """Parse chip n from lc ($D000-$EFFF, bank 1 at $D000) and the 64-byte chip
    table (None if unknown). Returns a disasm.Chip; parts and pins are named
    per chip (AND1, chip0_pin1, ...)."""
    for cls in (disasm.AND, disasm.OR, disasm.XOR, disasm.NOT, disasm.Node, disasm.FF, disasm.Chip):
        cls._index = 0
    chip = disasm.Chip(bytes(lc[n * CHIP_SIZE:(n + 1) * CHIP_SIZE]), name=f"chip{n}", format="CHP")
    if table is not None:
        chip._parsePIN(bytes(table[n * 8:n * 8 + 8]))
    return chip


def listing(title, lc, table):
    """Disassembly of all non-empty chips of one game state."""
    out = [f"# {title}"]
    if table is not None and not any(table):
        out.append("# (chip table all zero: pin directions unknown)")
        table = None
    empty = []
    for n in range(NUM_CHIPS):
        chip = disassemble(n, lc, table)
        if not chip.parts:
            empty.append(str(n))
            continue
        out += ["", f"# chip {n} at ${chip_address(n):04X}, {len(chip.chipData)} bytes", repr(chip)]
    if empty:
        out += ["", f"# empty: chip {', '.join(empty)}"]
    return "\n".join(out) + "\n"


def from_program_disks(side_a, side_b):
    disks = [Disk(side_a), Disk(side_b)]
    result = []
    for title, side, segments, tables in SETUPS:
        lc = empty_chips()
        for page, address, length in segments:
            lc[address - 0xD000:address - 0xD000 + length] = disks[side].read(page, (length + 255) // 256)[:length]
        table = bytearray(NUM_CHIPS * 8)
        for address, data in tables.items():
            table[address - TABLE:address - TABLE + len(data)] = data
        result.append((title, lc, table))
    return result


def from_state(path):
    main = parse_state(path)[0]["main"]
    # AppleWin keeps LC bank 1 ($D000-$DFFF) at $C000-$CFFF of its dump
    lc = main[0xC000:0xD000] + main[0xE000:0xF000]
    return [(path, lc, main[TABLE:TABLE + NUM_CHIPS * 8])]


def has_world(disk, page):
    p = disk.read(page + 0x1B, 2)
    return p[0x80] == 0x80 and p[0x100] == 0x7C


def from_storage_disk(path):
    """Saved games: slot k at page 117 + 107k = header ($5E00, chip table at
    +$00), $D000-$EFFF (32 pages), the world, the level code."""
    disk = Disk(path)
    directory = disk.linear(32)
    result = []
    for slot in range(4):
        first = 117 + 107 * slot
        if first + 107 > 560 or not has_world(disk, first + 33):
            continue
        name = bytes(b & 0x7F for b in directory[slot * 16:slot * 16 + 16]).decode("ascii").strip()
        result.append((f"slot {slot}: {name}", disk.read(first + 1, 32), disk.linear(first)[:NUM_CHIPS * 8]))
    return result


def main():
    args = sys.argv[1:]
    if len(args) == 2:
        states = from_program_disks(*args)
    elif len(args) == 1 and args[0].lower().endswith(".yaml"):
        states = from_state(args[0])
    elif len(args) == 1:
        states = from_storage_disk(args[0])
    else:
        sys.exit(__doc__)
    if not states:
        sys.exit("no saved games found")
    print("\n\n".join(listing(*s) for s in states), end="")


if __name__ == "__main__":
    main()
