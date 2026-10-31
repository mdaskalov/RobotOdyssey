#!/usr/bin/env python3
"""Measure the game's main-loop speed by running a save state on the emulator.

Usage: ro_timing.py STATE.aws.yaml [ITERATIONS] [MAINLOOP_HEX]

Runs the level's main loop (default $0841, Level 1) with no keys pressed and
reports CPU cycles per iteration ("tick") and the implied ticks per second on
a 1.0205 MHz Apple IIe.  The engine never waits for the vertical blank, so a
tick takes as long as its work does: the rate depends on what is on screen.
"""
import sys

from aws_state import parse_state
from cpu6502 import CPU

CPU_HZ = 1_020_484


class Machine:
    """64K main RAM + language card banking ($D000 bank 1/2) + counters for I/O."""

    def __init__(self, main):
        self.mem = bytearray(main)
        # AppleWin keeps LC bank 1 ($D000-$DFFF) at $C000-$CFFF of its dump
        self.bank1 = bytearray(main[0xC000:0xD000])
        self.bank = 2
        self.clicks = self.flips = 0
        self.cpu = CPU(self.mem)
        self.cpu.io_read = self.io
        self.cpu.io_write = lambda a, v: self.io(a)

    def io(self, a):
        if a == 0xC030:
            self.clicks += 1
        elif a in (0xC054, 0xC055):
            self.flips += 1
        elif 0xC080 <= a <= 0xC08F:
            want = 1 if a & 0x08 else 2
            if want != self.bank:                   # swap $D000-$DFFF with the other bank
                cur = bytes(self.mem[0xD000:0xE000])
                self.mem[0xD000:0xE000] = self.bank1
                self.bank1 = bytearray(cur)
                self.bank = want
        return 0                                    # no key, paddles read as 0


def main():
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    iterations = int(sys.argv[2]) if len(sys.argv) > 2 else 20
    loop = int(sys.argv[3], 16) if len(sys.argv) > 3 else 0x0841
    mem, regs = parse_state(sys.argv[1])
    m = Machine(mem["main"])
    cpu = m.cpu
    cpu.sp = 0xF0
    cpu.pc = loop
    last, ticks = cpu.cycles, []
    while len(ticks) < iterations:
        cpu.step()
        if cpu.pc == loop:
            ticks.append(cpu.cycles - last)
            last = cpu.cycles
    room = m.mem[0x6300]
    avg = sum(ticks) / len(ticks)
    print(f"room ${room:02X}: {len(ticks)} ticks, cycles/tick min {min(ticks)} avg {avg:.0f} max {max(ticks)}")
    print(f"  = {CPU_HZ / avg:.1f} ticks/s ({1000 * avg / CPU_HZ:.1f} ms/tick); "
          f"page flips {m.flips}, speaker clicks {m.clicks}")


if __name__ == "__main__":
    main()
