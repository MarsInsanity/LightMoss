#!/usr/bin/env python3
"""Draw the charging screen's images for U-Boot's charge mode.

U-Boot (drivers/power/charge_animation.c, ODROID-GO Advance flavour) loads
battery_0..3.bmp from BOOT while the device charges switched off: it starts at
the image for the current charge (<=5%, <=60%, <=80%, <=100%) and cycles up to
battery_3, so the bars fill up; battery_fail.bmp is for a battery it cannot
read. It prints the battery voltage and charge current below the picture, in
text rows 18 and 19, so the picture keeps to the upper half of the screen.

Full-screen 640x480 24-bit BMPs, the format U-Boot's show_bmp decodes (the
boot logo's). Plain Python, no dependencies:

    make-charge-images.py OUTPUT_DIR
"""

import os
import struct
import sys

W, H = 640, 480

BLACK = (0, 0, 0)
OUTLINE = (208, 208, 208)
GREEN = (126, 196, 82)
RED = (224, 64, 64)

# The battery: body, outline thickness, terminal nub on the right.
BX, BY, BW, BH = 196, 96, 236, 124
LINE = 6
NUB_W, NUB_H = 16, 44
# Four bars inside the body.
PAD = 8
BARS = 4


def canvas():
    return [[BLACK] * W for _ in range(H)]


def rect(img, x, y, w, h, color):
    for yy in range(max(0, y), min(H, y + h)):
        row = img[yy]
        for xx in range(max(0, x), min(W, x + w)):
            row[xx] = color


def battery(img):
    rect(img, BX, BY, BW, BH, OUTLINE)
    rect(img, BX + LINE, BY + LINE, BW - 2 * LINE, BH - 2 * LINE, BLACK)
    rect(img, BX + BW, BY + (BH - NUB_H) // 2, NUB_W, NUB_H, OUTLINE)


def bars(img, filled, color):
    ix, iy = BX + LINE + PAD, BY + LINE + PAD
    iw, ih = BW - 2 * (LINE + PAD), BH - 2 * (LINE + PAD)
    bar_w = (iw - (BARS - 1) * PAD) // BARS
    for i in range(filled):
        rect(img, ix + i * (bar_w + PAD), iy, bar_w, ih, color)


def cross(img, color):
    # A thick X across the inside of the battery.
    ix, iy = BX + LINE + PAD, BY + LINE + PAD
    iw, ih = BW - 2 * (LINE + PAD), BH - 2 * (LINE + PAD)
    for t in range(ih):
        x = ix + (iw - ih) // 2 + t
        rect(img, x - 4, iy + t, 9, 1, color)
        rect(img, x - 4, iy + ih - 1 - t, 9, 1, color)


def write_bmp(path, img):
    row_bytes = W * 3  # 1920, already a multiple of 4: no padding
    data = bytearray()
    for y in range(H - 1, -1, -1):  # BMP rows go bottom-up
        for r, g, b in img[y]:
            data += bytes((b, g, r))
    header = struct.pack("<2sIHHI", b"BM", 54 + len(data), 0, 0, 54)
    info = struct.pack("<IiiHHIIiiII", 40, W, H, 1, 24, 0, len(data),
                       2835, 2835, 0, 0)
    assert len(data) == row_bytes * H
    with open(path, "wb") as f:
        f.write(header + info + data)


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else "."
    os.makedirs(out, exist_ok=True)
    for n in range(4):
        img = canvas()
        battery(img)
        # battery_0 is the almost-empty one: a single red bar.
        bars(img, n + 1, RED if n == 0 else GREEN)
        write_bmp(os.path.join(out, "battery_%d.bmp" % n), img)
    img = canvas()
    battery(img)
    cross(img, RED)
    write_bmp(os.path.join(out, "battery_fail.bmp"), img)


if __name__ == "__main__":
    main()
