"""Dungeon props and pickups for the Collapsed Mines (isometric, bottom-centre origin).

Each sprite is drawn so its ground contact sits on the bottom row, centred, which is
where the interactable scenes place their origin. Colors are palette names
(palette.MATERIAL ramps); ground shadows are the separate shadow sprite, not baked.

    python tools/art/gen_props.py            writes assets/sprites/props/*.png
"""

from __future__ import annotations

from pathlib import Path

import palette
from pixel import Canvas, seeded

REPO_ROOT = Path(__file__).resolve().parents[2]
OUT_DIR = Path("assets/sprites/props")

M = palette.MATERIAL


def chest() -> Canvas:
    c = Canvas(32, 28)
    # Body: front face and lid as two shaded boxes with an iron band and lock.
    c.polygon([(3, 12), (16, 18), (16, 26), (3, 20)], M["timber"][2])
    c.polygon([(16, 18), (29, 12), (29, 20), (16, 26)], M["timber"][3])
    c.polygon([(3, 12), (16, 6), (29, 12), (16, 18)], M["timber"][0])
    c.polygon([(3, 8), (16, 2), (29, 8), (16, 14)], M["timber"][1])
    c.polygon([(3, 8), (16, 14), (16, 18), (3, 12)], M["timber"][2])
    c.polygon([(16, 14), (29, 8), (29, 12), (16, 18)], M["timber"][3])
    for x0, x1 in ((7, 9), (22, 24)):
        c.rect(x0, 7, x1, 20, M["iron"][1])
    c.rect(15, 15, 17, 19, M["gold"][1])
    c.put(16, 17, M["gold"][3])
    c.outline()
    return c


def shrine() -> Canvas:
    c = Canvas(32, 44)
    # Stone plinth with steps.
    c.polygon([(2, 34), (16, 41), (30, 34), (16, 27)], M["rock"][1])
    c.polygon([(2, 34), (16, 41), (16, 43), (2, 36)], M["rock"][2])
    c.polygon([(30, 34), (16, 41), (16, 43), (30, 36)], M["rock"][3])
    c.polygon([(8, 31), (16, 35), (24, 31), (16, 27)], M["rock"][0])
    c.rect(12, 20, 20, 30, M["rock"][2])
    c.rect(12, 20, 14, 30, M["rock"][1])
    # Floating echo crystal.
    c.polygon([(16, 3), (22, 13), (16, 23), (10, 13)], M["echo"][1])
    c.polygon([(16, 3), (10, 13), (16, 14)], M["echo"][0])
    c.polygon([(16, 14), (22, 13), (16, 23)], M["echo"][3])
    c.put(14, 9, "hit_flash")
    c.outline()
    return c


def rope_post() -> Canvas:
    c = Canvas(28, 44)
    c.rect(4, 8, 7, 40, M["timber"][1])
    c.rect(20, 8, 23, 40, M["timber"][2])
    c.rect(4, 6, 23, 10, M["timber"][0])
    c.rect(4, 10, 23, 11, M["timber"][3])
    # Coiled rope hanging from the beam.
    for i in range(7):
        y = 12 + i * 3
        c.line(10, y, 18, y + 1, M["copper"][1] if i % 2 == 0 else M["copper"][2])
    c.line(14, 34, 14, 40, M["copper"][2])
    c.outline()
    return c


def barrel() -> Canvas:
    c = Canvas(24, 28)
    c.ellipse_shaded(12, 15, 9, 11, M["timber"])
    for y in (9, 20):
        for x in range(4, 20):
            c.put(x, y, M["iron"][2])
    c.ellipse(12, 6, 8, 3, M["timber"][0])
    c.outline()
    return c


def mining_node() -> Canvas:
    c = Canvas(32, 28)
    rng = seeded("node")
    c.ellipse_shaded(16, 15, 13, 11, M["rock"])
    for _ in range(7):
        x = rng.randint(7, 24)
        y = rng.randint(9, 21)
        c.rect(x, y, x + 2, y + 1, M["ore"][1])
        c.put(x, y, M["ore"][0])
    c.outline()
    return c


def gold_nugget() -> Canvas:
    c = Canvas(14, 14)
    c.polygon([(2, 8), (5, 2), (10, 3), (12, 8), (7, 11)], M["gold"][1])
    c.polygon([(2, 8), (5, 2), (7, 6)], M["gold"][0])
    c.polygon([(7, 11), (12, 8), (9, 6)], M["gold"][2])
    c.put(5, 4, "hit_flash")
    c.outline()
    return c


PROPS = {
    "chest": chest,
    "shrine": shrine,
    "rope": rope_post,
    "breakable": barrel,
    "mining_node": mining_node,
    "pickup_gold": gold_nugget,
}


def build(root: Path) -> None:
    for name, fn in PROPS.items():
        fn().save(Path(root) / OUT_DIR / f"{name}.png")


if __name__ == "__main__":
    build(REPO_ROOT)
    print("props:", len(PROPS))
