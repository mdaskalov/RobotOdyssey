#!/usr/bin/env python3
"""Extract RAM from an AppleWin / Mariani save state (.aws.yaml).

Usage: aws_state.py STATE.yaml OUTDIR
Writes OUTDIR/main.bin (64K main RAM) and OUTDIR/aux.bin (64K aux RAM, if present).
"""
import re
import sys
from pathlib import Path


def parse_state(path):
    """Return dict with 'main' and 'aux' bytearrays (64K each) and CPU registers."""
    lines = Path(path).read_text().splitlines()
    mem = {}
    cpu = {}
    current = None
    for line in lines:
        s = line.strip()
        if s.startswith("Main Memory:"):
            current = "main"
            mem[current] = bytearray(0x10000)
            continue
        if s.startswith("Auxiliary Memory Bank00:"):
            current = "aux"
            mem[current] = bytearray(0x10000)
            continue
        m = re.fullmatch(r"([0-9A-F]{4}): ([0-9A-F]+)", s)
        if m and current:
            addr = int(m.group(1), 16)
            data = bytes.fromhex(m.group(2))
            mem[current][addr:addr + len(data)] = data
            continue
        current = None if not m else current
        m = re.fullmatch(r"(A|X|Y|P|S|PC): 0x([0-9A-F]+)", s)
        if m and "PC" not in cpu:
            cpu[m.group(1)] = int(m.group(2), 16)
    return mem, cpu


def main():
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    mem, cpu = parse_state(sys.argv[1])
    out = Path(sys.argv[2])
    out.mkdir(parents=True, exist_ok=True)
    for name, data in mem.items():
        (out / f"{name}.bin").write_bytes(data)
    print("CPU:", {k: hex(v) for k, v in cpu.items()})
    print("wrote", ", ".join(f"{k}.bin" for k in mem))


if __name__ == "__main__":
    main()
