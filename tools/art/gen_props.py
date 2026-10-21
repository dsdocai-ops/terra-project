"""Dungeon props and pickups for the Collapsed Mines (isometric, bottom-centre origin).

Each sprite is drawn so its ground contact sits on the bottom row, centred, which is
where the interactable scenes place their origin.
"""
import sys

import palette
from pixel import Canvas, seeded

R = palette.RAMPS


def chest():
    c = Canvas(32, 28)
    c.ellipse(16, 24, 14, 4, palette.SHADOW)
    # Body: front face and lid as two shaded boxes with an iron band and lock.
    c.polygon([(3, 12), (16, 18), (16, 26), (3, 20)], R["timber"][2])
    c.polygon([(16, 18), (29, 12), (29, 20), (16, 26)], R["timber"][3])
    c.polygon([(3, 12), (16, 6), (29, 12), (16, 18)], R["timber"][0])
    c.polygon([(3, 8), (16, 2), (29, 8), (16, 14)], R["timber"][1])
    c.polygon([(3, 8), (16, 14), (16, 18), (3, 12)], R["timber"][2])
    c.polygon([(16, 14), (29, 8), (29, 12), (16, 18)], R["timber"][3])
    for x0, x1 in ((7, 9), (22, 24)):
        c.rect(x0, 7, x1, 20, R["iron"][1])
    c.rect(15, 15, 17, 19, R["gold"][1])
    c.put(16, 17, R["gold"][3])
    c.outline()
    return c


def shrine():
    c = Canvas(32, 44)
    c.ellipse(16, 40, 14, 4, palette.SHADOW)
    # Stone plinth with steps.
    c.polygon([(2, 34), (16, 41), (30, 34), (16, 27)], R["rock"][1])
    c.polygon([(2, 34), (16, 41), (16, 43), (2, 36)], R["rock"][2])
    c.polygon([(30, 34), (16, 41), (16, 43), (30, 36)], R["rock"][3])
    c.polygon([(8, 31), (16, 35), (24, 31), (16, 27)], R["rock"][0])
    c.rect(12, 20, 20, 30, R["rock"][2])
    c.rect(12, 20, 14, 30, R["rock"][1])
    # Floating echo crystal with a glow.
    c.ellipse(16, 13, 9, 9, (181, 138, 240, 60))
    c.polygon([(16, 3), (22, 13), (16, 23), (10, 13)], R["echo"][1])
    c.polygon([(16, 3), (10, 13), (16, 14)], R["echo"][0])
    c.polygon([(16, 14), (22, 13), (16, 23)], R["echo"][3])
    c.put(14, 9, palette.WHITE)
    c.outline()
    return c


def rope_post():
    c = Canvas(28, 44)
    c.ellipse(14, 40, 12, 4, palette.SHADOW)
    c.rect(4, 8, 7, 40, R["timber"][1])
    c.rect(20, 8, 23, 40, R["timber"][2])
    c.rect(4, 6, 23, 10, R["timber"][0])
    c.rect(4, 10, 23, 11, R["timber"][3])
    # Coiled rope hanging from the beam.
    for i in range(7):
        y = 12 + i * 3
        c.line(10, y, 18, y + 1, R["copper"][1] if i % 2 == 0 else R["copper"][2])
    c.line(14, 34, 14, 40, R["copper"][2])
    c.outline()
    return c


def barrel():
    c = Canvas(24, 28)
    c.ellipse(12, 25, 10, 3, palette.SHADOW)
    c.ellipse_shaded(12, 15, 9, 11, R["timber"])
    for y in (9, 20):
        for x in range(4, 20):
            c.put(x, y, R["iron"][2])
    c.ellipse(12, 6, 8, 3, R["timber"][0])
    c.outline()
    return c


def mining_node():
    c = Canvas(32, 28)
    rng = seeded("node")
    c.ellipse(16, 24, 13, 4, palette.SHADOW)
    c.ellipse_shaded(16, 15, 13, 11, R["rock"])
    for _ in range(7):
        x = rng.randint(7, 24)
        y = rng.randint(9, 21)
        c.rect(x, y, x + 2, y + 1, R["ore"][1])
        c.put(x, y, R["ore"][0])
    c.outline()
    return c


def gold_nugget():
    c = Canvas(14, 14)
    c.ellipse(7, 12, 5, 2, palette.SHADOW)
    c.polygon([(2, 8), (5, 2), (10, 3), (12, 8), (7, 11)], R["gold"][1])
    c.polygon([(2, 8), (5, 2), (7, 6)], R["gold"][0])
    c.polygon([(7, 11), (12, 8), (9, 6)], R["gold"][2])
    c.put(5, 4, palette.WHITE)
    c.outline()
    return c


def build(out_dir):
    d = out_dir + "/props"
    chest().save(d + "/chest.png")
    shrine().save(d + "/shrine.png")
    rope_post().save(d + "/rope.png")
    barrel().save(d + "/breakable.png")
    mining_node().save(d + "/mining_node.png")
    gold_nugget().save(d + "/pickup_gold.png")


if __name__ == "__main__":
    build(sys.argv[1] if len(sys.argv) > 1 else "../../assets/sprites")
