"""16x16 relic icons (the twenty Week 4 relics) and the six pickup sprites.

Icons carry no rarity frame: the UI draws that around them in the rarity colour,
so one icon works on a charm, a choice tablet or the codex.

    py gen_icons.py <sprites_dir>
"""
import sys

import palette
from pixel import Canvas

R = palette.RAMPS
ramp = palette.ramp_from
HEX = palette.hex_rgb
W = palette.WHITE


def boot(c, sole, upper):
    c.polygon([(5, 4), (9, 4), (9, 9), (13, 10), (13, 13), (3, 13), (3, 9), (5, 9)], upper)
    c.rect(3, 12, 13, 13, sole)


def ember_boots():
    c = Canvas(16, 16)
    boot(c, R["iron"][3], R["cloth"][1])
    for x, y in ((6, 1), (7, 2), (6, 3), (8, 3)):
        c.put(x, y, HEX("#FF6A1F"))
    c.put(7, 3, HEX("#FFD23F")); c.put(7, 2, HEX("#FFD23F"))
    return c


def storm_sandals():
    c = Canvas(16, 16)
    boot(c, R["timber"][3], R["timber"][1])
    c.polygon([(10, 0), (7, 5), (9, 5), (6, 9), (12, 3), (10, 3)], HEX("#FFE14A"))
    return c


def mirror_step():
    c = Canvas(16, 16)
    for x0, col in ((2, R["relic"][1]), (9, R["relic"][2])):
        c.ellipse(x0 + 2, 9, 2, 3, col)
        c.ellipse(x0 + 2, 13, 1.5, 1.5, col)
    c.line(8, 2, 8, 14, W)
    return c


def frostwalkers():
    c = Canvas(16, 16)
    boot(c, R["relic"][2], ramp("#6AA8D8")[1])
    for dx, dy in ((0, -1), (0, 1), (-1, 0), (1, 0)):
        c.put(8 + dx, 2 + dy, W)
    c.put(8, 2, R["relic"][0])
    return c


def ghost_wrap():
    c = Canvas(16, 16)
    c.polygon([(4, 14), (4, 6), (8, 2), (12, 6), (12, 14), (10, 12), (8, 14), (6, 12)], ramp("#E8E8F0")[1])
    c.put(6, 7, palette.OUTLINE); c.put(10, 7, palette.OUTLINE); c.put(8, 9, palette.OUTLINE)
    return c


def rebound_spring():
    c = Canvas(16, 16)
    for i in range(5):
        y = 3 + i * 2
        c.line(4, y, 12, y + 1, R["iron"][0] if i % 2 == 0 else R["iron"][2])
    c.rect(3, 13, 12, 14, R["iron"][2])
    c.rect(3, 1, 12, 2, R["iron"][2])
    c.put(13, 7, R["gold"][0])
    return c


def echo_blade():
    c = Canvas(16, 16)
    c.line(3, 13, 11, 5, R["iron"][0])
    c.line(4, 13, 12, 5, R["iron"][1])
    c.line(2, 14, 4, 12, R["gold"][2])
    c.line(1, 10, 5, 14, R["timber"][2])
    for k in (0, 1):
        c.line(7 + k * 3, 3 + k, 14, 3 + k, R["echo"][1] if k == 0 else R["echo"][2])
    return c


def spark_plug():
    c = Canvas(16, 16)
    c.rect(6, 9, 9, 14, R["iron"][1])
    c.rect(5, 8, 10, 9, R["iron"][2])
    c.rect(7, 4, 8, 8, R["iron"][0])
    for x, y in ((3, 2), (11, 1), (12, 5), (2, 6)):
        c.put(x, y, HEX("#FFE14A"))
    c.line(7, 4, 10, 1, HEX("#FFE14A"))
    return c


def hungry_steel():
    c = Canvas(16, 16)
    c.polygon([(2, 5), (14, 5), (14, 12), (2, 12)], R["iron"][1])
    c.rect(2, 8, 14, 9, palette.OUTLINE)
    for x in range(3, 14, 2):
        c.put(x, 7, W); c.put(x, 10, W)
    c.put(5, 3, R["blood"][1]); c.put(10, 3, R["blood"][1])
    return c


def venom_gland():
    c = Canvas(16, 16)
    c.ellipse_shaded(8, 9, 5, 5, ramp("#7AC943"))
    c.polygon([(8, 1), (10, 5), (6, 5)], ramp("#7AC943")[1])
    c.put(6, 8, W)
    c.put(8, 14, HEX("#7AC943"))
    return c


def splitting_shot():
    c = Canvas(16, 16)
    c.line(2, 8, 8, 8, R["timber"][1])
    for dy in (-5, 0, 5):
        c.line(8, 8, 13, 8 + dy, R["iron"][0])
        c.put(14, 8 + dy, R["gold"][1])
    return c


def gravity_stone():
    c = Canvas(16, 16)
    c.ellipse_shaded(8, 8, 4, 4, R["rock"])
    for a in range(0, 360, 20):
        import math
        x = 8 + math.cos(math.radians(a)) * 7
        y = 8 + math.sin(math.radians(a)) * 3
        c.put(x, y, R["echo"][1])
    return c


def leech_fang():
    c = Canvas(16, 16)
    c.polygon([(5, 2), (11, 2), (10, 8), (8, 14), (6, 8)], ramp("#E8DCC8")[1])
    c.polygon([(5, 2), (8, 2), (7, 10), (6, 8)], ramp("#E8DCC8")[0])
    c.put(8, 14, R["blood"][1]); c.put(8, 15, R["blood"][2])
    return c


def rune_of_ricochet():
    c = Canvas(16, 16)
    c.ellipse_shaded(8, 8, 6, 6, R["rock"])
    c.line(4, 11, 8, 5, R["echo"][0]); c.line(8, 5, 12, 11, R["echo"][0])
    c.line(5, 8, 11, 8, R["echo"][1])
    return c


def volatile_core():
    c = Canvas(16, 16)
    c.ellipse_shaded(8, 8, 6, 6, ramp("#FF6A1F"))
    c.line(5, 5, 8, 8, palette.OUTLINE); c.line(8, 8, 11, 6, palette.OUTLINE); c.line(8, 8, 9, 12, palette.OUTLINE)
    c.put(7, 7, HEX("#FFD23F"))
    return c


def soul_jar():
    c = Canvas(16, 16)
    c.rect(5, 3, 10, 4, R["iron"][1])
    c.polygon([(4, 5), (11, 5), (12, 12), (11, 14), (4, 14), (3, 12)], ramp("#9CC8D8")[2])
    c.ellipse(8, 10, 3, 3, ramp("#B58AF0")[1])
    c.put(7, 9, W)
    return c


def bloodthirst():
    c = Canvas(16, 16)
    c.polygon([(8, 1), (13, 9), (8, 14), (3, 9)], R["blood"][1])
    c.polygon([(8, 1), (3, 9), (8, 9)], R["blood"][0])
    c.put(6, 8, W)
    return c


def corpse_bloom():
    c = Canvas(16, 16)
    c.ellipse_shaded(8, 11, 5, 4, ramp("#E8DCC8"))
    c.put(6, 11, palette.OUTLINE); c.put(10, 11, palette.OUTLINE)
    for dx, dy, col in ((-3, -5, "#F28CC9"), (0, -7, "#FFD23F"), (3, -5, "#F28CC9"), (0, -4, "#B58AF0")):
        c.ellipse(8 + dx, 8 + dy + 3, 2, 2, HEX(col))
    c.line(8, 8, 8, 6, ramp("#3F7A52")[1])
    return c


def domino():
    c = Canvas(16, 16)
    c.polygon([(5, 2), (11, 2), (11, 14), (5, 14)], ramp("#E8DCC8")[0])
    c.rect(5, 8, 11, 8, palette.OUTLINE)
    for x, y in ((7, 4), (9, 6), (7, 11), (9, 11), (7, 13), (9, 13)):
        c.put(x, y, palette.OUTLINE)
    return c


def trophy_belt():
    c = Canvas(16, 16)
    c.rect(1, 6, 14, 9, R["timber"][2])
    c.rect(1, 6, 14, 6, R["timber"][1])
    c.rect(6, 5, 9, 10, R["gold"][1])
    for x in (2, 12):
        c.ellipse(x + 1, 12, 1.6, 1.6, ramp("#E8DCC8")[0])
        c.put(x, 12, palette.OUTLINE); c.put(x + 2, 12, palette.OUTLINE)
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

def pickup_ore():
    c = Canvas(14, 14)
    c.ellipse(7, 12, 5, 2, palette.SHADOW)
    c.polygon([(2, 9), (4, 3), (9, 2), (12, 7), (10, 11), (4, 11)], R["rock"][2])
    c.polygon([(2, 9), (4, 3), (6, 6)], R["rock"][0])
    for x, y in ((6, 5), (8, 8), (4, 8)):
        c.rect(x, y, x + 1, y, R["ore"][1])
    c.outline()
    return c


def pickup_echo():
    c = Canvas(14, 14)
    c.ellipse(7, 12, 4, 2, palette.SHADOW)
    c.polygon([(7, 1), (11, 6), (7, 12), (3, 6)], R["echo"][1])
    c.polygon([(7, 1), (3, 6), (7, 6)], R["echo"][0])
    c.polygon([(7, 6), (11, 6), (7, 12)], R["echo"][3])
    c.put(5, 4, W)
    c.outline()
    return c


def pickup_rune():
    c = Canvas(14, 14)
    c.ellipse(7, 12, 5, 2, palette.SHADOW)
    c.polygon([(3, 10), (3, 3), (11, 3), (11, 10), (7, 12)], R["rock"][1])
    c.polygon([(3, 10), (3, 3), (6, 3), (6, 11)], R["rock"][0])
    c.line(5, 6, 9, 6, R["relic"][0]); c.line(7, 5, 7, 9, R["relic"][0]); c.put(5, 9, R["relic"][1]); c.put(9, 9, R["relic"][1])
    c.outline()
    return c


def pickup_relic():
    c = Canvas(14, 14)
    c.ellipse(7, 12, 5, 2, palette.SHADOW)
    c.ellipse(7, 7, 6, 6, (127, 214, 255, 50))
    c.polygon([(7, 1), (9, 5), (13, 5), (10, 8), (11, 12), (7, 10), (3, 12), (4, 8), (1, 5), (5, 5)], R["relic"][1])
    c.polygon([(7, 1), (5, 5), (1, 5), (4, 8), (7, 7)], R["relic"][0])
    c.put(6, 4, W)
    c.outline()
    return c


def pickup_potion():
    c = Canvas(14, 14)
    c.ellipse(7, 12, 5, 2, palette.SHADOW)
    c.rect(6, 1, 8, 3, R["timber"][1])
    c.polygon([(6, 3), (8, 3), (8, 6), (12, 11), (2, 11), (6, 6)], R["blood"][1])
    c.polygon([(6, 6), (8, 6), (12, 11), (2, 11)], R["blood"][2])
    c.put(5, 8, R["blood"][0]); c.put(4, 9, R["blood"][0])
    c.outline()
    return c


PICKUPS = {"ore": pickup_ore, "echo": pickup_echo, "rune": pickup_rune, "relic": pickup_relic, "potion": pickup_potion}


def build(sprites_dir):
    for name, fn in RELICS.items():
        c = fn()
        c.outline()
        c.save("%s/icons/relics/%s.png" % (sprites_dir, name))
    for name, fn in PICKUPS.items():
        fn().save("%s/props/pickup_%s.png" % (sprites_dir, name))


if __name__ == "__main__":
    build(sys.argv[1] if len(sys.argv) > 1 else "../../assets/sprites")
    print("icons:", len(RELICS), "relics,", len(PICKUPS), "pickups")
