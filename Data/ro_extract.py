#!/usr/bin/env python3
"""Extract Robot Odyssey I (Apple II, v1.0/v1.1) worlds from the disk images.

Usage:
    ro_extract.py SIDE_A.dsk SIDE_B.dsk OUTDIR [--rooms]

Writes into OUTDIR:
    <world>.bin        world memory image $6000-$94FF (0x3500 bytes)
    <world>.code.bin   level code image $0800-$1FFF
    <world>.json       decoded rooms, objects, texts, wires, robots
    <world>.png        8x8 sheet of all 64 rooms (room n at column n%8, row n//8)
    <world>/room_NN.png  every used room (with --rooms)
    font.bin           8 glyph rows x 96 chars ($A0-$FF), row 0 = bottom
    colors.bin         32 colours x 4 pattern bytes
"""
import json
import sys
from pathlib import Path

import apple2kit_data  # noqa: F401  (hires, dis6502: Apple2Kit's Data/)
from hires import write_png
from ro_render import render_room, to_rgb_rows, FONT, COLOR_TABLES
from ro_world import load_all, NUM_ROOMS


def contact_sheet(world, path, scale=1):
    w, h, gap = 280 * scale, 192 * scale, 4
    W, H = 8 * (w + gap), 8 * (h + gap)
    sheet = [bytearray([48, 48, 64] * W) for _ in range(H)]
    for r in range(NUM_ROOMS):
        if not world.room_is_used(r):
            continue
        rows = to_rgb_rows(render_room(world, r), scale)
        ox, oy = (r % 8) * (w + gap), (r // 8) * (h + gap)
        for y, row in enumerate(rows):
            sheet[oy + y][ox * 3:(ox + w) * 3] = bytes(row)
    write_png(path, W, H, sheet)


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    if len(args) != 3:
        sys.exit(__doc__)
    out = Path(args[2])
    out.mkdir(parents=True, exist_ok=True)
    worlds = load_all(args[0], args[1])
    for w in worlds:
        (out / f"{w.id}.bin").write_bytes(w.image())
        (out / f"{w.id}.code.bin").write_bytes(bytes(w.mem[0x0800:0x2000]))
        (out / f"{w.id}.json").write_text(json.dumps(w.to_json(), indent=1))
        contact_sheet(w, out / f"{w.id}.png")
        if "--rooms" in sys.argv:
            d = out / w.id
            d.mkdir(exist_ok=True)
            for r in range(NUM_ROOMS):
                if w.room_is_used(r):
                    write_png(d / f"room_{r:02X}.png", 560, 384, to_rgb_rows(render_room(w, r)))
        used = sum(1 for r in range(NUM_ROOMS) if w.room_is_used(r))
        print(f"{w.id:12s} {w.name:34s} rooms used: {used}")
    mem = worlds[0].mem
    (out / "font.bin").write_bytes(bytes(mem[FONT + 0xA0 + r * 0x60 + i] for r in range(8) for i in range(96)))
    (out / "colors.bin").write_bytes(bytes(mem[t + c] for c in range(32) for t in COLOR_TABLES))


if __name__ == "__main__":
    main()
