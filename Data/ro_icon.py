#!/usr/bin/env python3
"""Render the app icon: the blue robot (robot 2) as the engine draws it.

Usage: ro_icon.py STATE.yaml ICONSET_DIR

Draws Level 1 room 2 of the save state with the original routines -- objects
$9D18, robot exteriors $D2BC -- on a cleared page, with robots 0 and 1 hidden
and robot 2's thrusters off, and crops robot 2 (38x32 hi-res pixels).  The
icon is that pixel art, 20x20 per pixel, on a dark background with a soft
glow, full bleed (macOS applies the rounded mask).  Writes icon_N.png for
N = 16, 32, ... 1024 (each half of the next by 2x2 averaging) into ICONSET_DIR,
the app's Assets.xcassets/AppIcon.appiconset.
"""
import sys
from pathlib import Path

from aws_state import parse_state
import apple2kit_data  # noqa: F401  (hires, dis6502: Apple2Kit's Data/)
from hires import render, write_png
from ro_timing import Machine

SIZE, CELL = 1024, 20
OBJ_COLOR, OBJ_ROOM, CURRENT_ROOM = 0x6200, 0x6300, 0x9C2D
ROBOT2 = 0x8DCD + 2 * 0x1A                       # robot block: +$0C-$0F thrusters
BLACK = (0, 0, 0)
BLUE = (20, 207, 253)


def robot_pixels(state):
    """Rows of RGB tuples: robot 2 cropped from the room as the engine draws it."""
    m = Machine(parse_state(state)[0]["main"])
    mem = m.mem
    for body in (0xF0, 0xF1, 0xF2, 0xF3):        # robots 0 and 1: drawn black, no exteriors
        mem[OBJ_COLOR + body] = 0
        if body in (0xF0, 0xF2):
            mem[OBJ_ROOM + body] = 0x3F
    mem[ROBOT2 + 0x0C:ROBOT2 + 0x10] = bytes(4)
    mem[CURRENT_ROOM] = mem[OBJ_ROOM + 0xF4]
    pages = {b: bytes(mem[b:b + 0x2000]) for b in (0x2000, 0x4000)}
    m.cpu.sp = 0xF0
    m.cpu.call(0x9D03)                           # tiles: only to find the page drawn on
    base = next(b for b in pages if bytes(mem[b:b + 0x2000]) != pages[b])
    mem[base:base + 0x2000] = bytes(0x2000)
    for routine in (0x9D18, 0xD2BC):
        m.cpu.sp = 0xF0
        m.cpu.call(routine)
    rows = [[tuple(r[x * 3:x * 3 + 3]) for x in range(280)] for r in render(mem, base, scale=1)]
    lit = [(x, y) for y in range(192) for x in range(280) if rows[y][x] != BLACK]
    x0, x1 = min(x for x, _ in lit), max(x for x, _ in lit)
    y0, y1 = min(y for _, y in lit), max(y for _, y in lit)
    return [row[x0:x1 + 1] for row in rows[y0:y1 + 1]]


def solid(sprite):
    """Black pixels between blue ones on a row (the bar) stay black instead of background."""
    out = []
    for row in sprite:
        blue = [x for x, c in enumerate(row) if c == BLUE]
        out.append([c if c != BLACK or not blue or not blue[0] < x < blue[-1] else None
                    for x, c in enumerate(row)])
    return [[c if c is not None else (1, 1, 1) for c in row] for row in out]


def box_blur(img, w, h, r):
    for _ in range(3):
        img = [[tuple(sum(img[y][max(0, min(w - 1, x + d))][k] for d in range(-r, r + 1)) / (2 * r + 1)
                      for k in range(3)) for x in range(w)] for y in range(h)]
        img = [[tuple(sum(img[max(0, min(h - 1, y + d))][x][k] for d in range(-r, r + 1)) / (2 * r + 1)
                      for k in range(3)) for x in range(w)] for y in range(h)]
    return img


def icon(sprite):
    sh, sw = len(sprite), len(sprite[0])
    ox, oy = (SIZE - sw * CELL) // 2, (SIZE - sh * CELL) // 2

    def at(x, y):                                # sprite pixel under icon pixel (x, y), or None
        cx, cy = (x - ox) // CELL, (y - oy) // CELL
        if 0 <= cx < sw and 0 <= cy < sh and x >= ox and y >= oy and sprite[cy][cx] != BLACK:
            return sprite[cy][cx]
        return None

    # glow: the robot at 1/8 resolution, blurred
    g = SIZE // 8
    low = [[at(x * 8 + 4, y * 8 + 4) or BLACK for x in range(g)] for y in range(g)]
    low = box_blur(low, g, g, 4)

    def glow(x, y):                              # bilinear
        fx, fy = max(0.0, min(g - 1.001, x / 8 - 0.5)), max(0.0, min(g - 1.001, y / 8 - 0.5))
        ix, iy = int(fx), int(fy)
        tx, ty = fx - ix, fy - iy
        a, b, c, d = low[iy][ix], low[iy][ix + 1], low[iy + 1][ix], low[iy + 1][ix + 1]
        return [(a[k] * (1 - tx) + b[k] * tx) * (1 - ty) + (c[k] * (1 - tx) + d[k] * tx) * ty for k in range(3)]

    centre, edge = (18, 30, 60), (2, 4, 10)
    rows = []
    for y in range(SIZE):
        row = bytearray()
        for x in range(SIZE):
            p = at(x, y)
            if p is not None:
                shade = 0.82 if (y - oy) % CELL >= CELL - 3 else 1.0   # scan line between pixel rows
                row += bytes(int(v * shade) for v in p)
                continue
            d = min(1.0, ((x - SIZE / 2) ** 2 + (y - SIZE / 2) ** 2) ** 0.5 / (SIZE * 0.62)) ** 1.4
            gl = glow(x, y)
            row += bytes(min(255, int(centre[k] + (edge[k] - centre[k]) * d + gl[k] * 0.55)) for k in range(3))
        rows.append(row)
    return rows


def half(rows):
    n = len(rows) // 2
    return [bytes((rows[2 * y][6 * x + k] + rows[2 * y][6 * x + 3 + k]
                   + rows[2 * y + 1][6 * x + k] + rows[2 * y + 1][6 * x + 3 + k] + 2) // 4
                  for x in range(n) for k in range(3)) for y in range(n)]


def main():
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    out = Path(sys.argv[2])
    out.mkdir(parents=True, exist_ok=True)
    rows, size = icon(solid(robot_pixels(sys.argv[1]))), SIZE
    while size >= 16:
        write_png(out / f"icon_{size}.png", size, size, rows)
        rows, size = half(rows), size // 2


if __name__ == "__main__":
    main()
