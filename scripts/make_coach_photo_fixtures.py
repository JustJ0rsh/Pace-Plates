#!/usr/bin/env python3
"""Write two synthetic PNGs to add as the newest Simulator library images.

This only writes files. The test operator explicitly imports them into a chosen
Simulator; stock sample photos can remain. It does not access Photos, Health,
the app database, or any device.
"""
from pathlib import Path
import struct
import sys
import zlib

destination = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(__file__).resolve().parents[1] / ".tmp" / "coach-photo-fixtures"
destination.mkdir(parents=True, exist_ok=True)


def chunk(kind: bytes, data: bytes) -> bytes:
    return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data) & 0xFFFFFFFF)


for name, color in [("coach-blue.png", (35, 105, 215)), ("coach-orange.png", (235, 125, 35))]:
    width, height = 640, 800
    pixels = bytearray()
    for y in range(height):
        pixels.append(0)
        for x in range(width):
            inside = 160 <= x < 480 and 180 <= y < 620
            pixels.extend((245, 245, 245) if inside and ((x // 40 + y // 40) % 2 == 0) else color)
    encoded = b"\x89PNG\r\n\x1a\n"
    encoded += chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0))
    encoded += chunk(b"tEXt", b"Description\0Synthetic Coach UI test image; no personal content")
    encoded += chunk(b"IDAT", zlib.compress(pixels, level=9))
    encoded += chunk(b"IEND", b"")
    path = destination / name
    path.write_bytes(encoded)
    print(path)
