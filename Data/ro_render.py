#!/usr/bin/env python3
"""Draw a Robot Odyssey room the way the Apple II engine does.

Everything is drawn into a 280x192 hi-res byte buffer (40 bytes per line,
bit 7 = palette bit) using the engine's tables, then converted to RGB.

Coordinates: objects/texts use x = 0..139 (2 screen pixels each) and
y = 0..191 counted from the BOTTOM; screen line = 191 - y.
"""
from hires import write_png

FONT = 0x9460          # glyph row r of char c (c >= $A0) at FONT + r*$60 + c
COLOR_TABLES = (0x9B91, 0x9BB1, 0x9BD1, 0x9BF1)   # 4 pattern bytes per colour
BIG_TEXT_COLORS = (0xA4B9, 0xA4C1)                # not in the loaded engine part
BIG_TEXT_DEFAULT = ([0x00, 0x2A, 0x55, 0x7F, 0x80, 0xAA, 0xD5, 0xFF],
                    [0x00, 0x55, 0x2A, 0x7F, 0x80, 0xD5, 0xAA, 0xFF])


class Screen:
    def __init__(self):
        self.lines = [bytearray(40) for _ in range(192)]

    def plot(self, px, line, pattern):
        """Set hi-res pixel px (0..279) on a line to the pattern's bit."""
        if not (0 <= px < 280 and 0 <= line < 192):
            return
        b, bit = divmod(px, 7)
        pat = pattern[b & 1]
        row = self.lines[line]
        row[b] = (row[b] & 0x7F & ~(1 << bit)) | (pat & (1 << bit)) | (pat & 0x80)

    def plot_logical(self, x, y, pattern):
        """One 'colour pixel' at object coordinates (x, y)."""
        line = 191 - y
        self.plot(2 * x, line, pattern)
        self.plot(2 * x + 1, line, pattern)


def colour(mem, c):
    return [mem[t + (c & 0x1F)] for t in COLOR_TABLES]


def draw_tiles(scr, mem, walls, floor_c, wall_c):
    floor, wall = colour(mem, floor_c), colour(mem, wall_c)
    for r in range(12):
        for c in range(20):
            pat = wall if walls[r][c] else floor
            if pat[0] == 0xF0:                  # colour $14: leave untouched
                continue
            for i in range(16):
                line = r * 16 + i
                for b in (2 * c, 2 * c + 1):
                    scr.lines[line][b] = pat[(b + (2 if i & 1 else 0)) % 4]


def draw_sprite(scr, rows, x, y, pattern):
    """16 rows, row 0 at the bottom; bit 6 is the leftmost pixel.

    Like the engine's 7 pre-shifted routines ($AF5A...): every row with pixels
    rewrites all bytes it spans (2 for shift 0, else 3) with mask = pixels | $80,
    so those bytes take the pattern's palette bit; shift 0 also sets the palette
    bit of the third byte if that byte is empty.
    """
    if x >= 0x86 or y >= 0xB1:
        return
    b0, shift = divmod(2 * x, 7)
    span = 2 if shift == 0 else 3
    for r in range(16):
        bits = rows[r]
        if not bits:
            continue
        line = scr.lines[191 - (y + r)]
        masks = [0x80] * span
        for i in range(7):
            if bits & (0x40 >> i):
                for q in (shift + 2 * i, shift + 2 * i + 1):
                    masks[q // 7] |= 1 << (q % 7)
        for k, mask in enumerate(masks):
            b = b0 + k
            line[b] = (line[b] & ~mask & 0xFF) | (mask & pattern[b & 1])
        if shift == 0 and b0 + 2 < 40 and line[b0 + 2] == 0:
            line[b0 + 2] = 0x80 & pattern[0]


def plot_engine(scr, mem, x, y, c):
    """Plot one colour pixel with the engine's wire tables ($A14D): AND/OR masks
    per (colour, shift) for the byte and the next one; the palette bit is ORed."""
    row = scr.lines[191 - y]
    b, idx = mem[0x9B05 + x], ((c << 3) | mem[0x9A79 + x]) & 0xFF
    row[b] = (row[b] & mem[0xA201 + idx]) | mem[0xA181 + idx]
    if b + 1 < 40:
        row[b + 1] = (row[b + 1] & mem[0xA241 + idx]) | mem[0xA1C1 + idx]


def draw_wire(scr, mem, ax, ay, bx, by, c):
    """Wires are L-shaped: horizontal at A's y from ax to bx ($A04C), then
    vertical at B's x from ay to by ($9FC4); the corner is (bx, ay).  If the
    horizontal part is shorter than 4 units the vertical one ends up at
    max(ax, bx) + 1, as in the original."""
    clamp_x = lambda v: v if v < 0x8B else (0x8A if v < 0xCF else 0)
    clamp_y = lambda v: v if v < 0xC0 else (0xBF if v < 0xDF else 0)
    vx = bx
    if ay < 0xC0:
        lo, hi = sorted((clamp_x(ax), clamp_x(bx)))
        end = hi + 1
        if end - lo < 4:
            for x in range(lo, end):
                plot_engine(scr, mem, x, ay, c)
            vx = end            # engine quirk: the loop leaves its x ($18) at max+1
        else:                                       # byte-wise fill with end masks
            row = scr.lines[191 - ay]
            pat = (mem[0xA144 + c], mem[0xA13C + c])     # even / odd byte columns
            b, last = mem[0x9B05 + lo], mem[0x9B05 + end]
            keep = mem[0xA135 + mem[0x9A79 + lo]]
            row[b] = (row[b] & keep) | (~keep & 0xFF & pat[b & 1])
            b += 1
            while b < last:
                row[b] = pat[b & 1]
                b += 1
            keep = mem[0xA12E + mem[0x9A79 + end]]
            if b < 40:
                row[b] = (row[b] & keep) | (~keep & 0xFF & pat[b & 1])
    if vx < 0x8B:
        lo, hi = sorted((clamp_y(ay), clamp_y(by)))
        for y in range(lo, hi + 1):
            plot_engine(scr, mem, vx, y, c)


def draw_text(scr, mem, t):
    raw, x0, y = t["raw"], t["x"], t["y"]
    if t["style"] == 2:
        _draw_big_text(scr, mem, raw, x0, y, t["color"])
        return
    col0 = (2 * x0) // 7 if x0 < 0x8C else -((2 * ((-x0) & 0xFF)) // 7)
    col = col0
    for c in raw:
        if c == 0xA0:
            col += 1
        elif c > 0xA0:
            if 0 <= col < 40 and y < 0xB9:
                for r in range(8):
                    line = 191 - (y + r)
                    if 0 <= line < 192:
                        scr.lines[line][col] |= mem[FONT + r * 0x60 + c]
            col += 1
        else:                                   # carriage return
            y = (y - 9) & 0xFF
            col = col0


def _draw_big_text(scr, mem, raw, x0, y, c):
    pattern = (BIG_TEXT_DEFAULT[0][c & 7], BIG_TEXT_DEFAULT[1][c & 7])
    x = x0
    for ch in raw:
        if ch == 0x8D:
            x, y = x0, (y - 0x12) & 0xFF
            continue
        if ch != 0xA0 and x < 0x86 and y < 0xB1:
            rows = []
            for r in range(8):
                f = mem[FONT + r * 0x60 + ch]
                rev = int(f"{f:08b}"[::-1], 2) >> 1     # font bit 0 = left, sprite bit 6 = left
                rows += [rev, rev]
            draw_sprite(scr, rows, x, y, pattern)
        x += 7


def render_room(world, room):
    mem = world.mem
    scr = Screen()
    rm = world.room(room)
    draw_tiles(scr, mem, rm["walls"], rm["floor"], rm["wall"])
    objs = world.draw_list(room)
    for i in world.texts_in_room(room):
        draw_text(scr, mem, world.text(i))
    for o in objs:
        ob = world.obj(o)
        draw_sprite(scr, world.sprite(ob["sprite"] & 0x3F), ob["x"], ob["y"], colour(mem, ob["color"])[:2])
    for o in objs:                                  # wires ($FC62)
        w = world.wire(o)
        if w:
            draw_wire(scr, mem, w["ax"], w["ay"], w["bx"], w["by"], mem[0x6200 + o])
    for o in range(0xD1, 0xE0):                     # loose wires of objects $D1-$DF
        w = world.loose_wire(o)
        if mem[0x6300 + o] == room and w:
            draw_wire(scr, mem, w["ax"], w["ay"], w["bx"], w["by"], mem[0x6200 + o])
    return scr


# --- hi-res to RGB -----------------------------------------------------------
BLACK, WHITE = (0, 0, 0), (255, 255, 255)
PALETTE = {(0, 0): (255, 68, 253), (0, 1): (20, 245, 60),    # purple, green
           (1, 0): (20, 207, 253), (1, 1): (255, 106, 60)}    # blue, orange


def to_rgb_rows(scr, scale=2):
    rows = []
    for line in scr.lines:
        bits, pal = [], []
        for b in line:
            for i in range(7):
                bits.append((b >> i) & 1)
                pal.append(b >> 7)
        out = []
        for x in range(280):
            if bits[x]:
                if (x > 0 and bits[x - 1]) or (x < 279 and bits[x + 1]):
                    c = WHITE
                else:
                    c = PALETTE[(pal[x], x & 1)]
            elif 0 < x < 279 and bits[x - 1] and bits[x + 1]:
                c = PALETTE[(pal[x], (x - 1) & 1)]
            else:
                c = BLACK
            out.extend(c * scale)
        for _ in range(scale):
            rows.append(out)
    return rows


def save_room_png(world, room, path, scale=2):
    write_png(path, 280 * scale, 192 * scale, to_rgb_rows(render_room(world, room), scale))
