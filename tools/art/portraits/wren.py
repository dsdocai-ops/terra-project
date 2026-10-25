"""Wren, the miner (W5-B7): a 96x96 bust, front-facing, lit from the top left.

Layers from the back: shoulders and coat, neck, head, hair, helmet with its lantern.
Colors are palette names (palette.MATERIAL); the outline is added last.
"""

from __future__ import annotations

import palette
from pixel import Canvas

M = palette.MATERIAL
SIZE = 96


def draw() -> Canvas:
    c = Canvas(SIZE, SIZE)
    skin, hair, cloth = M["skin"], M["copper"], M["cloth"]
    # Shoulders and coat, with a strap and a collar.
    c.ellipse_shaded(48, 92, 40, 22, cloth)
    c.polygon([(30, 74), (38, 96), (46, 96), (40, 74)], M["timber"][2])
    c.polygon([(66, 74), (58, 96), (50, 96), (56, 74)], M["timber"][3])
    # Neck.
    c.rect(41, 62, 55, 78, skin[2])
    c.rect(41, 62, 44, 78, skin[3])
    # Hair behind the ears.
    c.ellipse(26, 50, 7, 14, hair[2])
    c.ellipse(70, 50, 7, 14, hair[3])
    # Head: a shadow edge on the lower right, the base tone, a lit patch top left.
    c.ellipse(50, 48, 21, 25, skin[3])
    c.ellipse(48, 46, 20, 24, skin[2])
    c.ellipse(44, 42, 13, 16, skin[1])
    # Ears.
    c.ellipse(27, 48, 3, 5, skin[2])
    c.ellipse(69, 48, 3, 5, skin[3])
    # Eyes with a highlight each, brows above, a small smile.
    for x in (39, 57):
        c.rect(x - 3, 46, x + 3, 50, "hit_flash")
        c.rect(x - 1, 46, x + 2, 50, M["iron"][3])
        c.put(x - 1, 46, "hit_flash")
        c.line(x - 5, 42, x + 4, 41, hair[3])
    c.line(48, 49, 47, 55, skin[3])
    c.line(42, 60, 54, 60, M["blood"][1])
    c.line(43, 61, 53, 61, M["blood"][2])
    # Soot smudge on the left cheek.
    c.rect(33, 54, 37, 56, M["ash"][2])
    # Fringe under the helmet.
    c.polygon([(28, 36), (36, 40), (44, 34), (52, 40), (60, 34), (68, 38), (66, 30), (30, 30)], hair[1])
    # Helmet: dome, brim and the lantern on the front.
    c.ellipse_shaded(48, 28, 26, 17, M["iron"])
    c.rect(22, 33, 74, 38, M["iron"][2])
    c.rect(22, 38, 74, 39, M["iron"][3])
    c.rect(44, 14, 52, 28, M["gold"][2])
    c.rect(45, 16, 51, 26, M["gold"][0])
    c.rect(47, 18, 49, 24, "hit_flash")
    c.outline()
    return c
