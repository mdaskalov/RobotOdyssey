#!/usr/bin/env python3
"""File catalog of Robot Odyssey I for the Apple II, versions 1.0 and 1.1.

Taken from the loader on track 1 ($4000-$4EFF, entry $4A20).  Every file is a
run of consecutive 256-byte pages in loader order (see ro_disk.py), loaded to
an arbitrary address.  A segment is (side, first_page, load_address, length).

The loader stores lengths as (full pages, bytes in last page); we keep bytes.
"""

def _len(pages, last):
    return pages * 256 + last


# Engine pieces shared by all worlds.  "main" is identical on both sides and
# holds the font ($9500-$97FF) and the colour/pattern tables ($9B91...).
ENGINE_MAIN = ("A", 129, 0x9500, _len(35, 215))

# Rest of the engine as loaded for the Robotropolis levels (side A).  $D000 and
# $F000 live in language-card RAM.
ENGINE_LEVELS = [("A", 247, 0x1A50, _len(5, 164)),
                 ("A", 266, 0xB8E0, _len(7, 32)),
                 ("A", 274, 0xD000, _len(15, 254)),
                 ("A", 290, 0xF000, _len(15, 244))]

# The world data lives at $6000-$94FF.  Code for a world is loaded at $0803
# (and sometimes $0B00/$14C0); see Docs/WorldFormat.md.  "exit" is the entry of
# the level code that runs when the player leaves for the next level (it
# rearranges the object table), with the bytes expected there.
WORLDS = [
    {
        "id": "level1", "name": "Level 1 - City Sewer", "side": "A", "kind": "level",
        "segments": [("A", 306, 0x6000, _len(34, 0)),
                     ("A", 253, 0x8200, _len(12, 217)),
                     ("A", 357, 0x8EF0, _len(5, 2))],
        "code": [("A", 340, 0x0803, _len(16, 223))],
        "exit": (0x0B93, "A9078D0062"),
    },
    # Levels 2-5 only load rooms/walls/text ($6E40-$81FF) and level code.
    # The object table is inherited from the previous level, modified by that
    # level's exit code (see ro_world.run_exit_script).
    {
        "id": "level2", "name": "Level 2 - Subway", "side": "A", "kind": "level", "base": "level1",
        "segments": [("A", 363, 0x6E40, _len(19, 192)), ("A", 400, 0x8EF0, _len(1, 63))],
        "code": [("A", 383, 0x0803, _len(16, 103))],
        "exit": (0x0B76, "A9078D0062"),
    },
    {
        "id": "level3", "name": "Level 3 - Town", "side": "A", "kind": "level", "base": "level2",
        "segments": [("A", 402, 0x6E40, _len(19, 192)), ("A", 441, 0x8EF0, _len(5, 249))],
        "code": [("A", 422, 0x0803, _len(18, 44))],
        "exit": (0x93BD, "A9078D0062"),
    },
    {
        "id": "level4", "name": "Level 4 - Master Computer Center", "side": "A", "kind": "level", "base": "level3",
        "segments": [("A", 447, 0x6E40, _len(19, 192)), ("A", 484, 0x8EF0, _len(5, 97))],
        "code": [("A", 467, 0x0803, _len(16, 98))],
        "exit": (0x0AFC, "20B61D"),
    },
    {
        "id": "level5", "name": "Level 5 - Skyways", "side": "A", "kind": "level", "base": "level4",
        "segments": [("A", 490, 0x6E40, _len(19, 192)), ("A", 529, 0x8EF0, _len(5, 217))],
        "code": [("A", 510, 0x0803, _len(18, 42))],
    },
    {
        "id": "anatomy", "name": "Robot Anatomy", "side": "B", "kind": "tutorial",
        "segments": [("B", 396, 0x6000, _len(53, 0))],
        "code": [("B", 348, 0x14C0, _len(11, 64)), ("B", 449, 0x0803, _len(4, 99)), ("B", 454, 0x14C0, _len(6, 121))],
    },
    {
        "id": "toolkit", "name": "Toolkit", "side": "B", "kind": "tutorial",
        "segments": [("B", 461, 0x6000, _len(53, 0))],
        "code": [("B", 348, 0x14C0, _len(11, 64)), ("B", 514, 0x0803, _len(9, 176)), ("B", 524, 0x14C0, _len(6, 20))],
    },
    {
        "id": "labtutorial", "name": "Innovation Lab Tutorial", "side": "B", "kind": "tutorial",
        "segments": [("B", 284, 0x6000, _len(53, 0))],
        "code": [("B", 337, 0x0803, _len(2, 251)), ("B", 168, 0x0B00, _len(20, 225)), ("B", 340, 0x0B00, _len(8, 0))],
    },
    {
        "id": "lab", "name": "Innovation Lab", "side": "B", "kind": "lab",
        "segments": [("B", 228, 0x6000, _len(53, 0))],
        "code": [("B", 281, 0x0803, _len(2, 248)), ("B", 168, 0x0B00, _len(20, 225))],
    },
]

WORLD_BY_ID = {w["id"]: w for w in WORLDS}
