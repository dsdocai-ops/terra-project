"""16x16 relic icons (the twenty Week 4 relics) and the five pickup sprites.

Icons carry no rarity frame: the UI draws that around them in the rarity colour,
so one icon works on a charm, a choice tablet or the codex. Colors are palette
names: palette.MATERIAL ramps, palette.ramp4 hue ramps, ELEMENT tints and the
qualified biome accents. Pickups bake no ground shadow (separate sprite).

    python tools/art/gen_icons.py
"""

from __future__ import annotations

import math
from pathlib import Path

import palette
from pixel import Canvas

REPO_ROOT = Path(__file__).resolve().parents[2]
RELIC_DIR = Path("assets/sprites/icons/relics")
PROP_DIR = Path("assets/sprites/props")

M = palette.MATERIAL
W = "hit_flash"
CRYSTAL = palette.biome("crystal_hollows")
PINK = CRYSTAL.accent_1_ref
STORM = "storm"
FIRE = "fire"
HOT = "yellow_light"
POISON = "poison"
BONE = M["bone"]
GREEN = palette.ramp4("green", high=True)
VIOLET = palette.ramp4("violet", high=True)


def boot(c: Canvas, sole: str, upper: str) -> None:
    c.polygon([(5, 4), (9, 4), (9, 9), (13, 10), (13, 13), (3, 13), (3, 9), (5, 9)], upper)
    c.rect(3, 12, 13, 13, sole)


def ember_boots() -> Canvas:
    c = Canvas(16, 16)
    boot(c, M["iron"][3], M["cloth"][1])
    for x, y in ((6, 1), (7, 2), (6, 3), (8, 3)):
        c.put(x, y, FIRE)
    c.put(7, 3, HOT)
    c.put(7, 2, HOT)
    return c


def storm_sandals() -> Canvas:
    c = Canvas(16, 16)
    boot(c, M["timber"][3], M["timber"][1])
    c.polygon([(10, 0), (7, 5), (9, 5), (6, 9), (12, 3), (10, 3)], STORM)
    return c


def mirror_step() -> Canvas:
    c = Canvas(16, 16)
    for x0, col in ((2, M["relic"][1]), (9, M["relic"][2])):
        c.ellipse(x0 + 2, 9, 2, 3, col)
        c.ellipse(x0 + 2, 13, 1.5, 1.5, col)
    c.line(8, 2, 8, 14, W)
    return c


def frostwalkers() -> Canvas:
    c = Canvas(16, 16)
    boot(c, M["relic"][2], "blue_light")
    for dx, dy in ((0, -1), (0, 1), (-1, 0), (1, 0)):
        c.put(8 + dx, 2 + dy, W)
    c.put(8, 2, M["relic"][0])
    return c


def ghost_wrap() -> Canvas:
    c = Canvas(16, 16)
    c.polygon([(4, 14), (4, 6), (8, 2), (12, 6), (12, 14), (10, 12), (8, 14), (6, 12)], "neutral_5")
    c.put(6, 7, "outline")
    c.put(10, 7, "outline")
    c.put(8, 9, "outline")
    return c


def rebound_spring() -> Canvas:
    c = Canvas(16, 16)
    for i in range(5):
        y = 3 + i * 2
        c.line(4, y, 12, y + 1, M["iron"][0] if i % 2 == 0 else M["iron"][2])
    c.rect(3, 13, 12, 14, M["iron"][2])
    c.rect(3, 1, 12, 2, M["iron"][2])
    c.put(13, 7, M["gold"][0])
    return c


def echo_blade() -> Canvas:
    c = Canvas(16, 16)
    c.line(3, 13, 11, 5, M["iron"][0])
    c.line(4, 13, 12, 5, M["iron"][1])
    c.line(2, 14, 4, 12, M["gold"][2])
    c.line(1, 10, 5, 14, M["timber"][2])
    for k in (0, 1):
        c.line(7 + k * 3, 3 + k, 14, 3 + k, M["echo"][1] if k == 0 else M["echo"][2])
    return c


def spark_plug() -> Canvas:
    c = Canvas(16, 16)
    c.rect(6, 9, 9, 14, M["iron"][1])
    c.rect(5, 8, 10, 9, M["iron"][2])
    c.rect(7, 4, 8, 8, M["iron"][0])
    for x, y in ((3, 2), (11, 1), (12, 5), (2, 6)):
        c.put(x, y, STORM)
    c.line(7, 4, 10, 1, STORM)
    return c


def hungry_steel() -> Canvas:
    c = Canvas(16, 16)
    c.polygon([(2, 5), (14, 5), (14, 12), (2, 12)], M["iron"][1])
    c.rect(2, 8, 14, 9, "outline")
    for x in range(3, 14, 2):
        c.put(x, 7, W)
        c.put(x, 10, W)
    c.put(5, 3, M["blood"][1])
    c.put(10, 3, M["blood"][1])
    return c


def venom_gland() -> Canvas:
    c = Canvas(16, 16)
    c.ellipse_shaded(8, 9, 5, 5, GREEN)
    c.polygon([(8, 1), (10, 5), (6, 5)], GREEN[1])
    c.put(6, 8, W)
    c.put(8, 14, POISON)
    return c


def splitting_shot() -> Canvas:
    c = Canvas(16, 16)
    c.line(2, 8, 8, 8, M["timber"][1])
    for dy in (-5, 0, 5):
        c.line(8, 8, 13, 8 + dy, M["iron"][0])
        c.put(14, 8 + dy, M["gold"][1])
    return c


def gravity_stone() -> Canvas:
    c = Canvas(16, 16)
    c.ellipse_shaded(8, 8, 4, 4, M["rock"])
    for a in range(0, 360, 20):
        x = 8 + math.cos(math.radians(a)) * 7
        y = 8 + math.sin(math.radians(a)) * 3
        c.put(x, y, M["echo"][1])
    return c


def leech_fang() -> Canvas:
    c = Canvas(16, 16)
    c.polygon([(5, 2), (11, 2), (10, 8), (8, 14), (6, 8)], BONE[1])
    c.polygon([(5, 2), (8, 2), (7, 10), (6, 8)], BONE[0])
    c.put(8, 14, M["blood"][1])
    c.put(8, 15, M["blood"][2])
    return c


def rune_of_ricochet() -> Canvas:
    c = Canvas(16, 16)
    c.ellipse_shaded(8, 8, 6, 6, M["rock"])
    c.line(4, 11, 8, 5, M["echo"][0])
    c.line(8, 5, 12, 11, M["echo"][0])
    c.line(5, 8, 11, 8, M["echo"][1])
    return c


def volatile_core() -> Canvas:
    c = Canvas(16, 16)
    c.ellipse_shaded(8, 8, 6, 6, ("orange_highlight", FIRE, "orange_base", "orange_dark"))
    c.line(5, 5, 8, 8, "outline")
    c.line(8, 8, 11, 6, "outline")
    c.line(8, 8, 9, 12, "outline")
    c.put(7, 7, HOT)
    return c


def soul_jar() -> Canvas:
    c = Canvas(16, 16)
    c.rect(5, 3, 10, 4, M["iron"][1])
    c.polygon([(4, 5), (11, 5), (12, 12), (11, 14), (4, 14), (3, 12)], "teal_base")
    c.ellipse(8, 10, 3, 3, VIOLET[1])
    c.put(7, 9, W)
    return c


def bloodthirst() -> Canvas:
    c = Canvas(16, 16)
    c.polygon([(8, 1), (13, 9), (8, 14), (3, 9)], M["blood"][1])
    c.polygon([(8, 1), (3, 9), (8, 9)], M["blood"][0])
    c.put(6, 8, W)
    return c


def corpse_bloom() -> Canvas:
    c = Canvas(16, 16)
    c.ellipse_shaded(8, 11, 5, 4, BONE)
    c.put(6, 11, "outline")
    c.put(10, 11, "outline")
    for dx, dy, col in ((-3, -5, PINK), (0, -7, HOT), (3, -5, PINK), (0, -4, VIOLET[1])):
        c.ellipse(8 + dx, 8 + dy + 3, 2, 2, col)
    c.line(8, 8, 8, 6, "green_dark")
    return c


def domino() -> Canvas:
    c = Canvas(16, 16)
    c.polygon([(5, 2), (11, 2), (11, 14), (5, 14)], BONE[0])
    c.rect(5, 8, 11, 8, "outline")
    for x, y in ((7, 4), (9, 6), (7, 11), (9, 11), (7, 13), (9, 13)):
        c.put(x, y, "outline")
    return c


def trophy_belt() -> Canvas:
    c = Canvas(16, 16)
    c.rect(1, 6, 14, 9, M["timber"][2])
    c.rect(1, 6, 14, 6, M["timber"][1])
    c.rect(6, 5, 9, 10, M["gold"][1])
    for x in (2, 12):
        c.ellipse(x + 1, 12, 1.6, 1.6, BONE[0])
        c.put(x, 12, "outline")
        c.put(x + 2, 12, "outline")
    return c


RELICS = {
    "ember_boots": ember_boots, "storm_sandals": storm_sandals, "mirror_step": mirror_step,
    "frostwalkers": frostwalkers, "ghost_wrap": ghost_wrap, "rebound_spring": rebound_spring,
    "echo_blade": echo_blade, "spark_plug": spark_plug, "hungry_steel": hungry_steel,
    "venom_gland": venom_gland, "splitting_shot": splitting_shot, "gravity_stone": gravity_stone,
    "leech_fang": leech_fang, "rune_of_ricochet": rune_of_ricochet, "volatile_core": volatile_core,
    "soul_jar": soul_jar, "bloodthirst": bloodthirst, "corpse_bloom": corpse_bloom,
    "domino": domino, "trophy_belt": trophy_belt,
}


# --- pickups (14x14, drawn bottom-aligned like the gold nugget) -----------------

def pickup_ore() -> Canvas:
    c = Canvas(14, 14)
    c.polygon([(2, 9), (4, 3), (9, 2), (12, 7), (10, 11), (4, 11)], M["rock"][2])
    c.polygon([(2, 9), (4, 3), (6, 6)], M["rock"][0])
    for x, y in ((6, 5), (8, 8), (4, 8)):
        c.rect(x, y, x + 1, y, M["ore"][1])
    c.outline()
    return c


def pickup_echo() -> Canvas:
    c = Canvas(14, 14)
    c.polygon([(7, 1), (11, 6), (7, 12), (3, 6)], M["echo"][1])
    c.polygon([(7, 1), (3, 6), (7, 6)], M["echo"][0])
    c.polygon([(7, 6), (11, 6), (7, 12)], M["echo"][3])
    c.put(5, 4, W)
    c.outline()
    return c


def pickup_rune() -> Canvas:
    c = Canvas(14, 14)
    c.polygon([(3, 10), (3, 3), (11, 3), (11, 10), (7, 12)], M["rock"][1])
    c.polygon([(3, 10), (3, 3), (6, 3), (6, 11)], M["rock"][0])
    c.line(5, 6, 9, 6, M["relic"][0])
    c.line(7, 5, 7, 9, M["relic"][0])
    c.put(5, 9, M["relic"][1])
    c.put(9, 9, M["relic"][1])
    c.outline()
    return c


def pickup_relic() -> Canvas:
    c = Canvas(14, 14)
    c.polygon([(7, 1), (9, 5), (13, 5), (10, 8), (11, 12), (7, 10), (3, 12), (4, 8), (1, 5), (5, 5)], M["relic"][1])
    c.polygon([(7, 1), (5, 5), (1, 5), (4, 8), (7, 7)], M["relic"][0])
    c.put(6, 4, W)
    c.outline()
    return c


def pickup_potion() -> Canvas:
    c = Canvas(14, 14)
    c.rect(6, 1, 8, 3, M["timber"][1])
    c.polygon([(6, 3), (8, 3), (8, 6), (12, 11), (2, 11), (6, 6)], M["blood"][1])
    c.polygon([(6, 6), (8, 6), (12, 11), (2, 11)], M["blood"][2])
    c.put(5, 8, M["blood"][0])
    c.put(4, 9, M["blood"][0])
    c.outline()
    return c


PICKUPS = {"ore": pickup_ore, "echo": pickup_echo, "rune": pickup_rune, "relic": pickup_relic, "potion": pickup_potion}


def build(root: Path) -> None:
    root = Path(root)
    for name, fn in RELICS.items():
        c = fn()
        c.outline()
        c.save(root / RELIC_DIR / f"{name}.png")
    for name, fn in PICKUPS.items():
        fn().save(root / PROP_DIR / f"pickup_{name}.png")


if __name__ == "__main__":
    build(REPO_ROOT)
    print("icons:", len(RELICS), "relics,", len(PICKUPS), "pickups")
