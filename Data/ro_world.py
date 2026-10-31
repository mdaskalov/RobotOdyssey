#!/usr/bin/env python3
"""Robot Odyssey (Apple II) world data: loading from disk and decoding.

A world is the memory image $6000-$94FF.  Layout (see Docs/WorldFormat.md):

  $6000 object tables, 10 arrays x 256 objects
  $6A00 sprites, 64 x 16 bytes
  $6E00 room tables, 8 arrays x 64 rooms
  $7000 room walls, 64 x 30 bytes
  $7880 text tables, 8 arrays x 128 entries, strings from $7C80
  $8200 robot table, $861C wire tables, $8EF0 level code/data
"""
from cpu6502 import CPU
from ro_catalog import WORLDS, WORLD_BY_ID, ENGINE_MAIN, ENGINE_LEVELS
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


def run_exit_script(mem, entry):
    """Run the level's exit code on the 6502 emulator (mem is modified).

    When the player leaves a level, its code rearranges the object table for
    the next level (moves objects in, parks the rest in room $3F, recolours
    the player...), shows a text screen, waits for a key and jumps to the
    "next level" handler (LDA #$02 / STA $02D0).  We run it from `entry` with
    ESC always pressed and stop at that handler.
    Returns {object: (old fields, new fields)} for the objects that changed.
    """
    addr, expect = entry
    if bytes(mem[addr:addr + len(expect) // 2]) != bytes.fromhex(expect):
        raise ValueError(f"exit code not found at ${addr:04X}")
    handler = bytes(mem).find(bytes.fromhex("A9028DD002"), 0x0803, 0x2000)
    before = bytes(mem[0x6000:0x6A00])
    cpu = CPU(mem)
    cpu.io_read = lambda a: 0x9B if a == 0xC000 else 0      # ESC held down
    # The level start-up code sets engine vectors (e.g. the draw routine at
    # $AEEB); it ends with LDA #0 / STA $9C51 just before the main loop.
    init_end = bytes(mem).find(bytes.fromhex("A9008D519C"), 0x0816, 0x0900) + 5
    cpu.call(0x0803, stop_at={init_end})
    cpu.sp = 0xFF
    cpu.call(addr, stop_at={handler})
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
        run_exit_script(mem, WORLD_BY_ID[w["base"]]["exit"])   # previous level's exit
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

    def __init__(self, mem, wid="", name=""):
        self.mem = mem
        self.id, self.name = wid, name

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
        m = self.mem
        if not m[0x861C + o]:
            return None
        return {"to": m[0x861C + o], "ax": m[0x871C + o], "ay": m[0x891C + o],
                "bx": m[0x881C + o], "by": m[0x8A1C + o]}

    def robots(self):
        return [{"object": self.mem[0x8200 + i], "interior": self.mem[0x8204 + i]} for i in range(4)]

    # --- export ----------------------------------------------------------
    def to_json(self):
        rooms = []
        for r in range(NUM_ROOMS):
            if not self.room_is_used(r):
                continue
            d = self.room(r)
            rooms.append({"room": r, "floor": d["floor"], "wall": d["wall"],
                          "links": {k: d[k] for k in ("up", "down", "left", "right")},
                          "walls": ["".join("#" if b else "." for b in row) for row in d["walls"]],
                          "objects": self.objects_in_room(r), "texts": self.texts_in_room(r)})
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
        out.append(World(mem, w["id"], w["name"]))
    return out
