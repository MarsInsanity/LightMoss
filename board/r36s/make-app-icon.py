#!/usr/bin/env python3
"""The LightMoss apps' icons: a 70x70 RGBA PNG (the size of spruce's own app
icons) on a moss-green rounded square: for LightMoss Update ("update", the
default) a white arrow down into a tray, for LightMoss Kernel ("kernel") a
white chip with pins.

    make-app-icon.py OUT.png [update|kernel]

Plain Python (zlib, struct), drawn with 4x4 supersampling for smooth edges,
so the build needs nothing beyond the host's python3.
"""
import struct
import sys
import zlib

SIZE = 70
SS = 4  # samples per pixel, per axis

BG = (79, 121, 66)        # moss green
FG = (255, 255, 255)


def in_rounded_square(x, y):
    r, lo, hi = 14.0, 2.0, SIZE - 2.0
    if not (lo <= x <= hi and lo <= y <= hi):
        return False
    cx = min(max(x, lo + r), hi - r)
    cy = min(max(y, lo + r), hi - r)
    return (x - cx) ** 2 + (y - cy) ** 2 <= r * r


def in_chip(x, y):
    # A chip: a square ring with a solid core, four pins on each side.
    if 20.0 <= x <= 50.0 and 20.0 <= y <= 50.0:
        ring = not (25.0 <= x <= 45.0 and 25.0 <= y <= 45.0)
        core = 30.0 <= x <= 40.0 and 30.0 <= y <= 40.0
        return ring or core
    for c in (24.0, 31.0, 38.0, 45.0):
        if c - 2.0 <= x <= c + 2.0 and (12.0 <= y < 20.0 or 50.0 < y <= 58.0):
            return True
        if c - 2.0 <= y <= c + 2.0 and (12.0 <= x < 20.0 or 50.0 < x <= 58.0):
            return True
    return False


GLYPH = "update"


def in_glyph(x, y):
    if GLYPH == "kernel":
        return in_chip(x, y)
    # Arrow: a shaft and a head pointing down.
    if 31.0 <= x <= 39.0 and 13.0 <= y <= 34.0:
        return True
    if 33.0 <= y <= 46.0:
        half = (46.0 - y) * 1.05
        if abs(x - 35.0) <= half:
            return True
    # Tray: a U under the arrow.
    if 50.0 <= y <= 56.0 and 16.0 <= x <= 54.0:
        return True
    if 42.0 <= y <= 56.0 and (16.0 <= x <= 22.0 or 48.0 <= x <= 54.0):
        return True
    return False


def pixel(px, py):
    bg = fg = 0
    for sy in range(SS):
        for sx in range(SS):
            x = px + (sx + 0.5) / SS
            y = py + (sy + 0.5) / SS
            if in_rounded_square(x, y):
                if in_glyph(x, y):
                    fg += 1
                else:
                    bg += 1
    n = SS * SS
    a = (bg + fg) / n
    if bg + fg == 0:
        return (0, 0, 0, 0)
    t = fg / (bg + fg)
    rgb = tuple(round(BG[i] * (1 - t) + FG[i] * t) for i in range(3))
    return rgb + (round(a * 255),)


def png(path):
    raw = bytearray()
    for y in range(SIZE):
        raw.append(0)  # filter: none
        for x in range(SIZE):
            raw.extend(pixel(x, y))

    def chunk(kind, data):
        c = kind + data
        return struct.pack(">I", len(data)) + c + struct.pack(">I", zlib.crc32(c) & 0xFFFFFFFF)

    ihdr = struct.pack(">IIBBBBB", SIZE, SIZE, 8, 6, 0, 0, 0)
    with open(path, "wb") as f:
        f.write(b"\x89PNG\r\n\x1a\n")
        f.write(chunk(b"IHDR", ihdr))
        f.write(chunk(b"IDAT", zlib.compress(bytes(raw), 9)))
        f.write(chunk(b"IEND", b""))


if __name__ == "__main__":
    if len(sys.argv) > 2:
        GLYPH = sys.argv[2]
    png(sys.argv[1])
