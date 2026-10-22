"""16x16 UI icons: the eight status effects, the two starting weapons, the menu
pointer and the potion flask, into assets/ui/icons/.

Status tints come from palette.ELEMENT (shared with VFX, pips and damage
numbers), everything else from palette.MATERIAL and the global steps.

    python tools/art/gen_ui.py
"""

from __future__ import annotations

import math
from pathlib import Path

import palette
from pixel import Canvas

REPO_ROOT = Path(__file__).resolve().parents[2]
OUT_DIR = Path("assets/ui/icons")

M = palette.MATERIAL
W = "hit_flash"


def burn() -> Canvas:
    c = Canvas(16, 16)
    c.polygon([(8, 1), (12, 7), (13, 11), (8, 15), (3, 11), (4, 7), (6, 6)], "fire")
    c.polygon([(8, 7), (11, 11), (8, 15), (5, 11)], "yellow_light")
    c.put(8, 10, W)
    return c


def chill() -> Canvas:
    c = Canvas(16, 16)
    col = "frost"
    c.line(8, 2, 8, 13, col)
    c.line(3, 5, 13, 10, col)
    c.line(13, 5, 3, 10, col)
    for x, y in ((8, 2), (8, 13), (3, 5), (13, 10), (13, 5), (3, 10)):
        c.put(x, y, W)
    return c


def freeze() -> Canvas:
    c = Canvas(16, 16)
    c.polygon([(3, 4), (12, 3), (13, 12), (4, 13)], "blue_highlight")
    c.polygon([(3, 4), (12, 3), (9, 8)], W)
    c.polygon([(13, 12), (4, 13), (9, 8)], "frost")
    return c


def shock() -> Canvas:
    c = Canvas(16, 16)
    c.polygon([(9, 1), (4, 9), (8, 9), (6, 15), (12, 6), (8, 6)], "storm")
    c.put(9, 3, W)
    return c


def toxin() -> Canvas:
    c = Canvas(16, 16)
    c.ellipse(8, 8, 5, 5, "poison")
    c.ellipse(7, 7, 2, 2, "green_highlight")
    c.put(6, 9, "outline")
    c.put(10, 9, "outline")
    c.put(8, 11, "outline")
    return c


def mark() -> Canvas:
    c = Canvas(16, 16)
    col = "neutral_6"
    for a in range(0, 360, 20):
        c.put(8 + math.cos(math.radians(a)) * 5, 8 + math.sin(math.radians(a)) * 5, col)
    c.line(8, 1, 8, 5, col)
    c.line(8, 11, 8, 15, col)
    c.line(1, 8, 5, 8, col)
    c.line(11, 8, 15, 8, col)
    c.put(8, 8, "hp_red")
    return c


def bleed() -> Canvas:
    c = Canvas(16, 16)
    c.polygon([(8, 1), (12, 8), (11, 12), (8, 14), (5, 12), (4, 8)], "blood")
    c.polygon([(8, 1), (4, 8), (5, 12), (8, 9)], "red_light")
    return c


def unravel() -> Canvas:
    c = Canvas(16, 16)
    col = "violet_light"
    pts = []
    for i in range(40):
        t = i / 39.0
        a = t * math.pi * 3.2
        r = 1 + t * 6
        pts.append((8 + math.cos(a) * r, 8 + math.sin(a) * r))
    for a, b in zip(pts, pts[1:]):
        c.line(a[0], a[1], b[0], b[1], col)
    return c


def pickaxe() -> Canvas:
    c = Canvas(16, 16)
    c.line(3, 14, 12, 5, M["timber"][1])
    c.line(4, 14, 13, 5, M["timber"][2])
    for k in range(-5, 6):
        c.put(8 + k, 3 + abs(k) // 2 + 1, M["iron"][1])
        c.put(8 + k, 3 + abs(k) // 2 + 2, M["iron"][2])
    c.put(3, 5, M["iron"][0])
    return c


def crossbow() -> Canvas:
    c = Canvas(16, 16)
    c.line(2, 8, 14, 8, M["timber"][1])
    c.line(3, 4, 3, 12, M["iron"][1])
    c.line(3, 4, 12, 7, M["copper"][2])
    c.line(3, 12, 12, 9, M["copper"][2])
    c.line(5, 8, 15, 8, M["iron"][0])
    c.put(14, 7, M["iron"][0])
    c.put(14, 9, M["iron"][0])
    return c


def pointer() -> Canvas:
    c = Canvas(16, 16)
    c.line(2, 14, 10, 6, M["timber"][1])
    c.line(3, 14, 11, 6, M["timber"][2])
    for k in range(-4, 5):
        c.put(10 + k, 2 + abs(k) // 2 + 1, M["iron"][0])
        c.put(10 + k, 2 + abs(k) // 2 + 2, M["iron"][1])
    return c


def flask() -> Canvas:
    c = Canvas(16, 16)
    c.rect(6, 1, 9, 3, M["timber"][1])
    c.polygon([(6, 3), (10, 3), (10, 6), (14, 13), (2, 13), (6, 6)], M["blood"][1])
    c.polygon([(6, 8), (10, 8), (14, 13), (2, 13)], M["blood"][2])
    c.put(5, 10, M["blood"][0])
    c.put(4, 11, M["blood"][0])
    return c


ICONS = {
    "status_burn": burn, "status_chill": chill, "status_freeze": freeze, "status_shock": shock,
    "status_toxin": toxin, "status_mark": mark, "status_bleed": bleed, "status_unravel": unravel,
    "weapon_pickaxe": pickaxe, "weapon_crossbow": crossbow, "pointer": pointer, "potion_flask": flask,
}


def build(root: Path) -> None:
    for name, fn in ICONS.items():
        c = fn()
        c.outline()
        c.save(Path(root) / OUT_DIR / f"{name}.png")


if __name__ == "__main__":
    build(REPO_ROOT)
    print("ui icons:", len(ICONS))
