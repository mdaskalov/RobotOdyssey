#!/usr/bin/env python3
"""Robot Odyssey (Apple II) disk access.

The game does not use DOS 3.3; its own loader reads whole tracks.  Within a
track, consecutive memory pages come from these .dsk (DOS-order) sectors:
"""
from pathlib import Path

# .dsk sector holding the k-th page of a track, as read by the game's loader
TRACK_PAGE_ORDER = [0x0, 0x6, 0x5, 0x4, 0x3, 0x2, 0x1, 0xF, 0xE, 0xD, 0xC, 0xB, 0xA, 0x9, 0x8, 0x7]
DSK_TO_PAGE = {s: k for k, s in enumerate(TRACK_PAGE_ORDER)}
DISK_SIZE = 35 * 16 * 256


class Disk:
    def __init__(self, path):
        self.path = Path(path)
        self.data = self.path.read_bytes()
        if len(self.data) != DISK_SIZE:
            raise ValueError(f"{path}: not a 140K .dsk image")

    def linear(self, n):
        """256-byte page number n in game (loader) order: track n//16, page n%16."""
        t, k = divmod(n, 16)
        off = t * 4096 + TRACK_PAGE_ORDER[k] * 256
        return self.data[off:off + 256]

    def read(self, first, count):
        return b"".join(self.linear(first + i) for i in range(count))

    def image(self):
        """Whole disk rearranged into loader order (560 pages)."""
        return self.read(0, 560)


def dsk_to_linear(track, sector):
    return track * 16 + DSK_TO_PAGE[sector]
