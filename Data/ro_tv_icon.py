#!/usr/bin/env python3
"""Render the tvOS brand assets: the layered app icon and the Top Shelf images.

Usage: ro_tv_icon.py STATE.yaml SIDE_A.dsk BRANDASSETS_DIR

App icon (400x240 @1x/@2x, App Store 1280x768): the macOS icon's robot
(ro_icon.py: robot 2, Scanner, as the engine draws it) on two layers for the
parallax -- Front: the pixel art, transparent around it; Back: the dark
background with the robot's glow.  Top Shelf (1920x720) and Top Shelf Wide
(2320x720), @1x/@2x: the game's title screen (ro_title.py, screen 2) 6x per
pixel at @2x, its black transparent over the same background and glow.
@1x is @2x halved by 2x2 averaging, like the macOS sizes.  Writes the whole
BRANDASSETS_DIR (Contents.json files included), the tvOS target's
Assets.xcassets/App Icon & Top Shelf Image.brandassets.
"""
import json
import struct
import sys
import zlib
from pathlib import Path

import apple2kit_data  # noqa: F401  (hires: Apple2Kit's Data/)
from hires import render
from ro_disk import Disk
from ro_icon import BLACK, box_blur, robot_pixels, solid
import ro_title

CENTRE, EDGE = (18, 30, 60), (2, 4, 10)      # background, as ro_icon.py
LOW = 8                                     # background and glow computed at 1/8


def write_png(path, width, rows, alpha):
    raw = b"".join(b"\x00" + bytes(r) for r in rows)

    def chunk(tag, data):
        c = tag + data
        return struct.pack(">I", len(data)) + c + struct.pack(">I", zlib.crc32(c) & 0xFFFFFFFF)

    head = struct.pack(">IIBBBBB", width, len(rows), 8, 6 if alpha else 2, 0, 0, 0)
    Path(path).write_bytes(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", head)
                           + chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b""))


def placed(sprite, w, h, cell):
    """(sprite, cell, x0, y0): the sprite centred on a w x h canvas."""
    return sprite, cell, (w - len(sprite[0]) * cell) // 2, (h - len(sprite) * cell) // 2


def background(w, h, art, glow):
    """Rows of RGB bytes: radial gradient plus the art's blurred glow, bilinear from 1/8."""
    sprite, cell, x0, y0 = art
    gw, gh = w // LOW, h // LOW

    def lit(x, y):
        cx, cy = (x - x0) // cell, (y - y0) // cell
        if x >= x0 and y >= y0 and 0 <= cy < len(sprite) and 0 <= cx < len(sprite[0]):
            return sprite[cy][cx] or BLACK
        return BLACK

    low = box_blur([[lit(x * LOW + LOW // 2, y * LOW + LOW // 2) for x in range(gw)] for y in range(gh)],
                   gw, gh, 4)
    for y in range(gh):
        for x in range(gw):
            dx, dy = (x + 0.5) / gw - 0.5, (y + 0.5) / gh - 0.5
            d = min(1.0, (dx * dx + dy * dy) ** 0.5 / 0.62) ** 1.4
            low[y][x] = [CENTRE[k] + (EDGE[k] - CENTRE[k]) * d + low[y][x][k] * glow for k in range(3)]

    def axis(n, m):                          # output pixel -> (low index, next, weight)
        out = []
        for i in range(n):
            f = max(0.0, min(m - 1.001, i / LOW - 0.5))
            out.append((int(f), int(f) + 1, f - int(f)))
        return out

    xs = axis(w, gw)
    wide = [[v for a, b, t in xs for v in (r[a][k] * (1 - t) + r[b][k] * t for k in range(3))] for r in low]
    rows = []
    for a, b, t in axis(h, gh):
        ra, rb = wide[a], wide[b]
        rows.append(bytearray(min(255, int(p + (q - p) * t)) for p, q in zip(ra, rb)))
    return rows


def draw(rows, art, channels):
    """The art onto rows (RGB, or RGBA: opaque art), last rows of each cell darkened (scan lines)."""
    sprite, cell, x0, y0 = art
    dark = max(1, round(cell * 3 / 20))
    for sy, line in enumerate(sprite):
        for r in range(cell):
            shade = 0.82 if r >= cell - dark else 1.0
            row = rows[y0 + sy * cell + r]
            for sx, c in enumerate(line):
                if c is not None:
                    px = bytes(int(v * shade) for v in c) + (b"\xff" if channels == 4 else b"")
                    x = (x0 + sx * cell) * channels
                    row[x:x + cell * channels] = px * cell
    return rows


def half(rows, channels):
    n, w = len(rows) // 2, len(rows[0]) // channels // 2
    c = channels
    return [bytes((rows[2 * y][2 * c * x + k] + rows[2 * y][2 * c * x + c + k]
                   + rows[2 * y + 1][2 * c * x + k] + rows[2 * y + 1][2 * c * x + c + k] + 2) // 4
                  for x in range(w) for k in range(c)) for y in range(n)]


def contents(path, data):
    path.mkdir(parents=True, exist_ok=True)
    data["info"] = {"author": "xcode", "version": 1}
    (path / "Contents.json").write_text(json.dumps(data, indent=2) + "\n")


def icon_stack(out, robot, w, h, cell, scales):
    """Front/Back image stack; w x h and cell are the largest scale's."""
    art = placed(robot, w, h, cell)
    layers = {"Front": (draw([bytearray(w * 4) for _ in range(h)], art, 4), 4),
              "Back": (background(w, h, art, 0.55), 3)}
    contents(out, {"layers": [{"filename": f"{n}.imagestacklayer"} for n in layers]})
    for name, (rows, ch) in layers.items():
        layer = out / f"{name}.imagestacklayer"
        contents(layer, {})
        imageset = layer / "Content.imageset"
        imageset.mkdir(parents=True, exist_ok=True)
        images, width = [], w
        for scale in scales:                 # largest first
            fn = f"{name.lower()}_{width}.png"
            write_png(imageset / fn, width, rows, ch == 4)
            images.append({"filename": fn, "idiom": "tv", "scale": scale})
            rows, width = half(rows, ch), width // 2
        contents(imageset, {"images": images[::-1]})


def top_shelf(out, title, w, h, cell):
    art = placed(title, w, h, cell)
    rows = draw(background(w, h, art, 0.3), art, 3)
    out.mkdir(parents=True, exist_ok=True)
    write_png(out / f"top_shelf_{w}.png", w, rows, False)
    write_png(out / f"top_shelf_{w // 2}.png", w // 2, half(rows, 3), False)
    contents(out, {"images": [{"filename": f"top_shelf_{w // 2}.png", "idiom": "tv", "scale": "1x"},
                              {"filename": f"top_shelf_{w}.png", "idiom": "tv", "scale": "2x"}]})


def title_screen(disk):
    """Title screen 2 (the logo) as rows of RGB tuples, black None."""
    mem = ro_title.load(Disk(disk))
    for p in ro_title.title_sequence(mem)[1]:
        ro_title.draw_picture(mem, p)
    rows = render(bytes(mem[ro_title.BUFFER:ro_title.BUFFER + 0x2000]), 0, scale=1)
    return [[c if c != BLACK else None for c in (tuple(r[x * 3:x * 3 + 3]) for x in range(280))] for r in rows]


def main():
    if len(sys.argv) != 4:
        sys.exit(__doc__)
    out = Path(sys.argv[3])
    robot = [[c if c != BLACK else None for c in row] for row in solid(robot_pixels(sys.argv[1]))]
    title = title_screen(sys.argv[2])
    icon_stack(out / "App Icon.imagestack", robot, 800, 480, 10, ("2x", "1x"))
    icon_stack(out / "App Icon - App Store.imagestack", robot, 1280, 768, 16, ("1x",))
    top_shelf(out / "Top Shelf Image.imageset", title, 3840, 1440, 6)
    top_shelf(out / "Top Shelf Image Wide.imageset", title, 4640, 1440, 6)
    contents(out, {"assets": [
        {"filename": "App Icon - App Store.imagestack", "idiom": "tv", "role": "primary-app-icon", "size": "1280x768"},
        {"filename": "App Icon.imagestack", "idiom": "tv", "role": "primary-app-icon", "size": "400x240"},
        {"filename": "Top Shelf Image Wide.imageset", "idiom": "tv", "role": "top-shelf-image-wide", "size": "2320x720"},
        {"filename": "Top Shelf Image.imageset", "idiom": "tv", "role": "top-shelf-image", "size": "1920x720"},
    ]})


if __name__ == "__main__":
    main()
