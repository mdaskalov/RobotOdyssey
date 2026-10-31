#!/usr/bin/env python3
"""Robot Odyssey (Apple II) world data: loading from disk and decoding.

A world is the memory image $6000-$94FF.  Layout (see Docs/WorldFormat.md):

  $6000 object tables, 10 arrays x 256 objects
  $6A00 sprites, 64 x 16 bytes
  $6E00 room tables, 8 arrays x 64 rooms
  $7000 room walls, 64 x 30 bytes
  $7880 text tables, 8 arrays x 128 entries, strings from $7C80
  $8200 robot table, $861C wire tables, $8EF0 level code/data
(the tutorials and the lab keep their wire tables in their code, see ro_catalog)
"""
from cpu6502 import CPU
from dis6502 import OPS, _modes as MODE_LENGTH
from ro_catalog import WORLDS, WORLD_BY_ID, ENGINE_MAIN, ENGINE_LEVELS, LEVEL_WIRES
from ro_disk import Disk

WORLD_BASE = 0x6000
WORLD_END = 0x9500
NUM_OBJECTS = 256
NUM_ROOMS = 64
NUM_SPRITES = 64
NUM_TEXTS = 128

OBJECT_FIELDS = ["next", "sprite", "color", "room", "x", "y", "link", "dx", "dy", "flags"]
ROOM_FIELDS = ["first", "floor", "wall", "up", "down", "right", "left", "unused"]
NOWHERE = 0x3F          # room used for objects that are not in the world
NO_OBJECT = 0xFF


class DiskSet:
    """Side A and side B of the program disk."""

    def __init__(self, side_a, side_b=None):
        self.sides = {"A": Disk(side_a)}
        if side_b:
            self.sides["B"] = Disk(side_b)

    def read(self, seg):
        side, page, _addr, length = seg
        disk = self.sides[side]
        pages = (length + 255) // 256
        return disk.read(page, pages)[:length]


def load_segments(diskset, mem, segments):
    for seg in segments:
        data = diskset.read(seg)
        addr = seg[2]
        mem[addr:addr + len(data)] = data


def find_exit_entry(mem):
    """Entry of the level's exit code, or None (level 5 has none).

    The exit code ends with LDY #next / JMP handler, where the handler starts
    LDA #$02 / STA $02D0.  Its entry is the lowest address before that point
    which is the target of a JMP/JSR from elsewhere and from which straight-line
    code (no RTS/RTI/BRK, no JMP away) runs into the LDY.  The addresses differ
    between v1.0 and v1.1 (e.g. level 2: $0B6F vs $0B76).
    """
    m = bytes(mem)
    handler = m.find(bytes.fromhex("A9028DD002"), 0x0803, 0x2000)
    if handler < 0:
        return None
    jmp = bytes([0x4C, handler & 0xFF, handler >> 8])
    regions = ((0x0803, 0x2000), (0x8EF0, 0x9500))
    sites = [i - 2 for lo, hi in regions for i in range(lo + 2, hi - 2) if m[i:i + 3] == jmp and m[i - 2] == 0xA0]
    if len(sites) != 1:
        return None
    site = sites[0]
    targets = sorted({t for lo, hi in regions for i in range(lo, hi - 2) if m[i] in (0x4C, 0x20)
                      for t in [m[i + 1] | m[i + 2] << 8] if site - 0x200 <= t <= site and not t <= i <= site})
    for t in targets:
        pc = t
        while pc < site:
            op = m[pc]
            if op not in OPS or OPS[op][0] in ("RTS", "RTI", "BRK") or op == 0x6C:
                break
            if op == 0x4C and m[pc + 1] | m[pc + 2] << 8 != pc + 3:
                break
            pc += MODE_LENGTH[OPS[op][1]]
        if pc == site:
            return t
    return None


def trace_code(mem, entry, area):
    """Addresses of the instruction bytes reachable from entry inside area
    (a range), following branches and JSR/JMP; None at an invalid opcode or BRK."""
    code, pending = set(), [entry]
    while pending:
        pc = pending.pop()
        while pc in area and pc not in code:
            op = mem[pc]
            if op not in OPS or OPS[op][0] == "BRK":
                return None
            mn, mode = OPS[op]
            code.update(range(pc, pc + MODE_LENGTH[mode]))
            if mode == "rel":
                pending.append(pc + 2 + (mem[pc + 1] ^ 0x80) - 0x80)
            if mn == "JSR" or (mn == "JMP" and mode == "abs"):
                pending.append(mem[pc + 1] | mem[pc + 2] << 8)
            if mn in ("JMP", "RTS", "RTI"):
                break
            pc += MODE_LENGTH[mode]
    return code


def run_exit_script(mem):
    """Run the level's exit code on the 6502 emulator (mem is modified).

    When the player leaves a level, its code rearranges the object table for
    the next level (moves objects in, parks the rest in room $3F, recolours
    the player...), shows a text screen, waits for a key and jumps to the
    "next level" handler (LDA #$02 / STA $02D0).  We run it with ESC always
    pressed and stop at that handler.
    Returns {object: (old fields, new fields)} for the objects that changed.
    """
    entry = find_exit_entry(mem)
    if entry is None:
        raise ValueError("exit code not found")
    handler = bytes(mem).find(bytes.fromhex("A9028DD002"), 0x0803, 0x2000)
    before = bytes(mem[0x6000:0x6A00])
    cpu = CPU(mem)
    cpu.io_read = lambda a: 0x9B if a == 0xC000 else 0      # ESC held down
    # The level start-up code sets engine vectors (e.g. the draw routine at
    # $AEEB); it ends with LDA #0 / STA $9C51 just before the main loop.
    init_end = bytes(mem).find(bytes.fromhex("A9008D519C"), 0x0816, 0x0900) + 5
    cpu.call(0x0803, stop_at={init_end})
    cpu.sp = 0xFF
    cpu.call(entry, stop_at={handler})
    changed = {}
    for i in range(NUM_OBJECTS):
        old = [before[k * 256 + i] for k in range(10)]
        new = [mem[0x6000 + k * 256 + i] for k in range(10)]
        if old != new:
            changed[i] = (old, new)
    return changed


def build_world_memory(diskset, world_id, cache=None):
    """Return a 64K bytearray with the world (and its code) loaded."""
    cache = {} if cache is None else cache
    if world_id in cache:
        return bytearray(cache[world_id])
    w = WORLD_BY_ID[world_id]
    if "base" in w:
        mem = build_world_memory(diskset, w["base"], cache)
        run_exit_script(mem)                    # previous level's exit code
        mem[0x0803:0x2000] = bytes(0x2000 - 0x0803)
    else:
        mem = bytearray(0x10000)
    load_segments(diskset, mem, [ENGINE_MAIN])
    if w["kind"] == "level":
        load_segments(diskset, mem, ENGINE_LEVELS)
    load_segments(diskset, mem, w["segments"])
    load_segments(diskset, mem, w["code"])
    cache[world_id] = bytes(mem)
    return mem


class World:
    """Decoded view of a world memory image (64K array, world at $6000)."""

    def __init__(self, mem, wid="", name="", wires=LEVEL_WIRES):
        self.mem = mem
        self.id, self.name = wid, name
        self.wires = wires          # base of the wire tables ("to" array)

    def image(self):
        return bytes(self.mem[WORLD_BASE:WORLD_END])

    # --- objects -------------------------------------------------------
    def obj(self, i):
        return {f: self.mem[0x6000 + k * 0x100 + i] for k, f in enumerate(OBJECT_FIELDS)}

    def objects_in_room(self, room):
        """Objects in drawing order: the room's linked list, then any stragglers."""
        seen, order = set(), []
        o = self.mem[0x6E00 + room]
        while o != NO_OBJECT and o not in seen and len(order) < 256:
            if self.mem[0x6300 + o] != room:
                break
            seen.add(o)
            order.append(o)
            o = self.mem[0x6000 + o]
        order += [i for i in range(NUM_OBJECTS) if i not in seen and self.mem[0x6300 + i] == room]
        return order

    def draw_list(self, room):
        """Objects exactly as the engine draws them ($9D18): follow the room's
        list from $6E00 until $FF, at most 255 objects."""
        order, o = [], self.mem[0x6E00 + room]
        while o != NO_OBJECT and len(order) < 255:
            order.append(o)
            o = self.mem[0x6000 + o]
        return order

    def sprite(self, n):
        return self.mem[0x6A00 + n * 16:0x6A00 + n * 16 + 16]

    # --- rooms ---------------------------------------------------------
    def room(self, r):
        d = {f: self.mem[0x6E00 + k * 0x40 + r] for k, f in enumerate(ROOM_FIELDS)}
        d["walls"] = self.walls(r)
        return d

    def walls(self, r):
        """12 rows x 20 columns of 0/1, row 0 at the top of the screen."""
        d = self.mem[0x7000 + r * 30:0x7000 + r * 30 + 30]
        grid = [[0] * 20 for _ in range(12)]
        for band in range(3):
            for col in range(20):
                nib = (d[band * 10 + col // 2] >> (4 * (col & 1))) & 15
                for k in range(4):
                    grid[band * 4 + k][col] = (nib >> k) & 1
        return grid

    def room_is_used(self, r):
        return any(self.mem[0x7000 + r * 30:0x7000 + r * 30 + 30]) or self.objects_in_room(r) or self.texts_in_room(r)

    def code_rooms(self):
        """Rooms whose wall bytes hold 6502 code: {room: (caller, entry)}.

        The world's code ($0803-$1FFF, $8EF0-$94FF) calls a routine in the wall
        table with JSR/JMP.  Followed through branches and JSR/JMP inside the
        table until RTS/RTI/JMP, it must contain only valid opcodes (no BRK),
        and every room it covers must lead back to itself on all four sides.
        """
        m, walls = self.mem, range(0x7000, 0x7000 + NUM_ROOMS * 30)
        found = {}
        for lo, hi in ((0x0803, 0x2000), (0x8EF0, 0x9500)):
            for site in range(lo, hi - 2):
                if m[site] not in (0x20, 0x4C):
                    continue
                entry = m[site + 1] | m[site + 2] << 8
                code = trace_code(m, entry, walls) if entry in walls else None
                if not code:
                    continue
                rooms = sorted({(a - walls.start) // 30 for a in code})
                if all(m[0x6E00 + k * 0x40 + r] == r for r in rooms for k in (3, 4, 5, 6)):
                    for r in rooms:
                        found.setdefault(r, (site, entry))
        return found

    # --- texts ---------------------------------------------------------
    def text(self, i):
        m = self.mem
        ptr = m[0x7B80 + i] | m[0x7C00 + i] << 8
        raw = bytearray()
        while m[ptr] and len(raw) < 1024:
            raw.append(m[ptr])
            ptr += 1
        return {"room": m[0x7880 + i], "x": m[0x7900 + i], "y": m[0x7980 + i],
                "style": m[0x7A00 + i], "color": m[0x7B00 + i], "raw": bytes(raw),
                "text": "".join("\n" if c & 0x7F == 0x0D else chr(c & 0x7F) for c in raw)}

    def texts_in_room(self, r):
        return [i for i in range(NUM_TEXTS) if self.mem[0x7880 + i] == r and self.mem[0x7B80 + i] | self.mem[0x7C00 + i] << 8]

    # --- wires / robots ------------------------------------------------
    def wire(self, o):
        m, w = self.mem, self.wires + o
        if not m[w]:
            return None
        return {"to": m[w], "ax": m[w + 0x100], "ay": m[w + 0x300], "bx": m[w + 0x200], "by": m[w + 0x400]}

    def loose_wire(self, o):
        """Wire of a loose wire object $D1-$DF ($8A82... in the levels), or None."""
        m, w = self.mem, self.wires + 0x466 + o
        if not m[w]:
            return None
        return {"ax": m[w + 0x0F], "ay": m[w + 0x2D], "bx": m[w + 0x1E], "by": m[w + 0x3C]}

    def robots(self):
        return [{"object": self.mem[0x8200 + i], "interior": self.mem[0x8204 + i]} for i in range(4)]

    # --- export ----------------------------------------------------------
    def to_json(self):
        rooms = []
        code_rooms = self.code_rooms()
        for r in range(NUM_ROOMS):
            if not self.room_is_used(r):
                continue
            d = self.room(r)
            rooms.append({"room": r, "floor": d["floor"], "wall": d["wall"],
                          "links": {k: d[k] for k in ("up", "down", "left", "right")},
                          "walls": ["".join("#" if b else "." for b in row) for row in d["walls"]],
                          "objects": self.objects_in_room(r), "texts": self.texts_in_room(r)})
            if r in code_rooms:
                caller, entry = code_rooms[r]
                rooms[-1]["code"] = {"caller": caller, "entry": entry}
        objects = []
        for i in range(NUM_OBJECTS):
            o = self.obj(i)
            o["id"] = i
            w = self.wire(i)
            if w:
                o["wire"] = w
            objects.append(o)
        texts = []
        for i in range(NUM_TEXTS):
            t = self.text(i)
            if t["raw"]:
                t.pop("raw")
                t["id"] = i
                texts.append(t)
        return {"id": self.id, "name": self.name, "robots": self.robots(),
                "rooms": rooms, "objects": objects, "texts": texts}


def load_all(side_a, side_b):
    ds = DiskSet(side_a, side_b)
    cache = {}
    out = []
    for w in WORLDS:
        if w["side"] not in ds.sides:
            continue
        mem = build_world_memory(ds, w["id"], cache)
        out.append(World(mem, w["id"], w["name"], w.get("wires", LEVEL_WIRES)))
    return out
