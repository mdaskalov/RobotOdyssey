#!/usr/bin/env python3
"""Check the room renderer against the original engine, running on the emulator.

Usage: ro_verify.py STATE.aws.yaml

For every room, sets the current room ($9C2D) in the save state's RAM and calls
the engine's own drawing routines in main-loop order -- tiles $9D03, texts
$A2A2, objects $9D18, wires $FC62 -- then compares the hi-res page they drew
with ro_render.render_room() byte for byte.
"""
import sys

from aws_state import parse_state
import apple2kit_data  # noqa: F401  (hires, dis6502: Apple2Kit's Data/)
from hires import row_addr
from ro_render import render_room
from ro_timing import Machine
from ro_world import World

DRAW_ROUTINES = (0x9D03, 0xA2A2, 0x9D18, 0xFC62)


def engine_draw(main, room):
    m = Machine(main)
    m.mem[0x9C2D] = room
    pages = {base: bytes(m.mem[base:base + 0x2000]) for base in (0x2000, 0x4000)}
    for addr in DRAW_ROUTINES:
        m.cpu.sp = 0xF0
        m.cpu.call(addr)
    # the page the engine drew on: the one that changed (or either, if it already showed this room)
    base = next((b for b in pages if bytes(m.mem[b:b + 0x2000]) != pages[b]), 0x2000)
    return m, [bytes(m.mem[row_addr(y, base):row_addr(y, base) + 40]) for y in range(192)]


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    main_ram = parse_state(sys.argv[1])[0]["main"]
    bad = 0
    for room in range(64):
        m, engine = engine_draw(main_ram, room)
        mine = render_room(World(m.mem), room)
        diff = [y for y in range(192) if bytes(mine.lines[y]) != engine[y]]
        if diff:
            bad += 1
            print(f"room ${room:02X}: {len(diff)} lines differ, first at line {diff[0]}")
    print(f"{64 - bad}/64 rooms identical to the engine's drawing")


if __name__ == "__main__":
    main()
