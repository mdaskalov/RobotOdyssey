#!/usr/bin/env python3
"""Draw the six maze spots where a Level 1 game puts the black crystal.

Usage: ro_shuffle.py SIDE_A.dsk SIDE_B.dsk OUT.png

L1_SHUFFLE_OBJECTS ($10F8) puts the black crystal ($04, black on the black
floor) in maze room L1_SHUFFLE_MAZE_ROOMS[i] at L1_SHUFFLE_CRYSTAL_X/Y[i],
i = RANDOM_BELOW_A 6 (Engine.md, Level 1: the shuffled objects). Each spot is
drawn like the engine with the crystal in white, chip 1 ($E7, shuffled too)
left out: rooms $08 $0C $07 in the top row, $06 $17 $16 below.
"""
import sys

from hires import write_png
from ro_render import render_room, to_rgb_rows
from ro_world import load_all

CRYSTAL, CHIP = 0x04, 0xE7
MAZE_ROOMS, CRYSTAL_X, CRYSTAL_Y = 0x11BC, 0x11CE, 0x11D4
GAP, GREY = 8, [60, 60, 60]


def main():
    if len(sys.argv) != 4:
        sys.exit(__doc__)
    world = next(w for w in load_all(sys.argv[1], sys.argv[2]) if w.id == "level1")
    mem = world.mem
    start = bytes(mem)
    panels = []
    for i in range(6):
        mem[:] = start
        room = mem[MAZE_ROOMS + i]
        mem[0x6300 + CHIP] = 0x3F
        mem[0x6E00 + mem[0x6300 + CRYSTAL]] = 0xFF  # out of room $07's list (it holds only $04)
        mem[0x6E00 + room] = CRYSTAL                # the maze rooms hold nothing else ($0C: $E7)
        mem[0x6000 + CRYSTAL] = 0xFF
        mem[0x6300 + CRYSTAL] = room
        mem[0x6400 + CRYSTAL] = mem[CRYSTAL_X + i]
        mem[0x6500 + CRYSTAL] = mem[CRYSTAL_Y + i]
        mem[0x6200 + CRYSTAL] = 7                   # white instead of black
        print(f"{i}: room ${room:02X} at (${mem[CRYSTAL_X + i]:02X}, ${mem[CRYSTAL_Y + i]:02X})")
        panels.append(to_rgb_rows(render_room(world, room), 1))
    rows = []
    for r in range(2):
        if r:
            rows += [GREY * (3 * 280 + 2 * GAP) for _ in range(GAP)]
        for line in range(192):
            out = []
            for c in range(3):
                out += panels[3 * r + c][line] + GREY * GAP * (c < 2)
            rows.append(out)
    write_png(sys.argv[3], 3 * 280 + 2 * GAP, 2 * 192 + GAP, rows)


if __name__ == "__main__":
    main()
