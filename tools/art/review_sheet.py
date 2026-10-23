"""Contact sheet for the art review step (SPEC-art-audio, "Review step").

Each image is drawn at 1x and 4x on the town ground colour with its file name under
it, and a strip of every distinct colour used sits at the bottom, so a reviewer sees
the asset, the zoom and the palette in one PNG.

    python tools/art/review_sheet.py <out.png> <image> [<image> ...]
"""

from __future__ import annotations

import sys
from pathlib import Path

from PIL import Image, ImageDraw

BACKGROUND = (0x3A, 0x34, 0x30)
LABEL = (0xE8, 0xD8, 0xB0)
MARGIN = 12
ZOOM = 4


def sheet(paths: list[Path], max_width: int = 1600) -> Image.Image:
    tiles: list[tuple[str, Image.Image]] = []
    colors: set[tuple[int, int, int]] = set()
    for path in paths:
        img = Image.open(path).convert("RGBA")
        colors |= {(r, g, b) for r, g, b, a in img.getdata() if a}
        tiles.append((path.stem, img))
    # Layout: rows of (1x | 4x) pairs, wrapping at max_width.
    x, y, row_h, placed = MARGIN, MARGIN, 0, []
    for name, img in tiles:
        w, h = img.width * (1 + ZOOM) + MARGIN, img.height * ZOOM + 14
        if x + w > max_width and x > MARGIN:
            x, y, row_h = MARGIN, y + row_h + MARGIN, 0
        placed.append((name, img, x, y))
        x += w + MARGIN
        row_h = max(row_h, h)
    height = y + row_h + MARGIN + 40
    out = Image.new("RGB", (max_width, height), BACKGROUND)
    draw = ImageDraw.Draw(out)
    for name, img, px, py in placed:
        out.paste(img, (px, py), img)
        big = img.resize((img.width * ZOOM, img.height * ZOOM), Image.NEAREST)
        out.paste(big, (px + img.width + MARGIN, py), big)
        draw.text((px, py + big.height + 1), name, fill=LABEL)
    for i, color in enumerate(sorted(colors)):
        sx = MARGIN + i * 16
        if sx + 14 > max_width:
            break
        draw.rectangle((sx, height - 30, sx + 13, height - 16), fill=color)
    draw.text((MARGIN, height - 12), f"{len(colors)} colours", fill=LABEL)
    return out


if __name__ == "__main__":
    if len(sys.argv) < 3:
        sys.exit(__doc__)
    sheet([Path(p) for p in sys.argv[2:]]).save(sys.argv[1])
    print("review sheet:", sys.argv[1])
