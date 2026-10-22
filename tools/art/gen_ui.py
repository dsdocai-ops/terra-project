"""16x16 UI icons: the eight status effects, the two starting weapons and the
menu pointer. Drawn into assets/ui/icons/. Colours come from palette.py.

    py gen_ui.py <ui_dir>
"""
import math
import sys

import palette
from pixel import Canvas

R = palette.RAMPS
HEX = palette.hex_rgb
W = palette.WHITE


def burn():
    c = Canvas(16, 16)
    c.polygon([(8, 1), (12, 7), (13, 11), (8, 15), (3, 11), (4, 7), (6, 6)], HEX("#FF6A1F"))
    c.polygon([(8, 7), (11, 11), (8, 15), (5, 11)], HEX("#FFD23F"))
    c.put(8, 10, W)
    return c


def chill():
    c = Canvas(16, 16)
    col = HEX("#7FD6FF")
    c.line(8, 2, 8, 13, col); c.line(3, 5, 13, 10, col); c.line(13, 5, 3, 10, col)
    for x, y in ((8, 2), (8, 13), (3, 5), (13, 10), (13, 5), (3, 10)):
        c.put(x, y, W)
    return c


def freeze():
    c = Canvas(16, 16)
    c.polygon([(3, 4), (12, 3), (13, 12), (4, 13)], HEX("#BFEAFF"))
    c.polygon([(3, 4), (12, 3), (9, 8)], W)
    c.polygon([(13, 12), (4, 13), (9, 8)], HEX("#7FD6FF"))
    return c


def shock():
    c = Canvas(16, 16)
    c.polygon([(9, 1), (4, 9), (8, 9), (6, 15), (12, 6), (8, 6)], HEX("#FFE14A"))
    c.put(9, 3, W)
    return c


def toxin():
    c = Canvas(16, 16)
    c.ellipse(8, 8, 5, 5, HEX("#7AC943"))
    c.ellipse(7, 7, 2, 2, HEX("#B6F078"))
    c.put(6, 9, palette.OUTLINE); c.put(10, 9, palette.OUTLINE); c.put(8, 11, palette.OUTLINE)
    return c


def mark():
    c = Canvas(16, 16)
    col = HEX("#E8DCC8")
    for a in range(0, 360, 20):
        c.put(8 + math.cos(math.radians(a)) * 5, 8 + math.sin(math.radians(a)) * 5, col)
    c.line(8, 1, 8, 5, col); c.line(8, 11, 8, 15, col); c.line(1, 8, 5, 8, col); c.line(11, 8, 15, 8, col)
    c.put(8, 8, HEX("#D83A3A"))
    return c


def bleed():
    c = Canvas(16, 16)
    c.polygon([(8, 1), (12, 8), (11, 12), (8, 14), (5, 12), (4, 8)], HEX("#C81E32"))
    c.polygon([(8, 1), (4, 8), (5, 12), (8, 9)], HEX("#FF6A7A"))
    return c


def unravel():
    c = Canvas(16, 16)
    col = HEX("#D933BF")
    pts = []
    for i in range(40):
        t = i / 39.0
        a = t * math.pi * 3.2
        r = 1 + t * 6
        pts.append((8 + math.cos(a) * r, 8 + math.sin(a) * r))
    for a, b in zip(pts, pts[1:]):
        c.line(a[0], a[1], b[0], b[1], col)
    return c


def pickaxe():
    c = Canvas(16, 16)
    c.line(3, 14, 12, 5, R["timber"][1])
    c.line(4, 14, 13, 5, R["timber"][2])
    for k in range(-5, 6):
        c.put(8 + k, 3 + abs(k) // 2 + 1, R["iron"][1])
        c.put(8 + k, 3 + abs(k) // 2 + 2, R["iron"][2])
    c.put(3, 5, R["iron"][0])
    return c


def crossbow():
    c = Canvas(16, 16)
    c.line(2, 8, 14, 8, R["timber"][1])
    c.line(3, 4, 3, 12, R["iron"][1])
    c.line(3, 4, 12, 7, R["copper"][2]); c.line(3, 12, 12, 9, R["copper"][2])
    c.line(5, 8, 15, 8, R["iron"][0])
    c.put(14, 7, R["iron"][0]); c.put(14, 9, R["iron"][0])
    return c


def pointer():
    c = Canvas(16, 16)
    c.line(2, 14, 10, 6, R["timber"][1])
    c.line(3, 14, 11, 6, R["timber"][2])
    for k in range(-4, 5):
        c.put(10 + k, 2 + abs(k) // 2 + 1, R["iron"][0])
        c.put(10 + k, 2 + abs(k) // 2 + 2, R["iron"][1])
    return c


def flask():
    c = Canvas(16, 16)
    c.rect(6, 1, 9, 3, R["timber"][1])
    c.polygon([(6, 3), (10, 3), (10, 6), (14, 13), (2, 13), (6, 6)], R["blood"][1])
    c.polygon([(6, 8), (10, 8), (14, 13), (2, 13)], R["blood"][2])
    c.put(5, 10, R["blood"][0]); c.put(4, 11, R["blood"][0])
    return c


ICONS = {
    "status_burn": burn, "status_chill": chill, "status_freeze": freeze, "status_shock": shock,
    "status_toxin": toxin, "status_mark": mark, "status_bleed": bleed, "status_unravel": unravel,
    "weapon_pickaxe": pickaxe, "weapon_crossbow": crossbow, "pointer": pointer, "potion_flask": flask,
}


def build(ui_dir):
    for name, fn in ICONS.items():
        c = fn()
        c.outline()
        c.save("%s/icons/%s.png" % (ui_dir, name))


if __name__ == "__main__":
    build(sys.argv[1] if len(sys.argv) > 1 else "../../assets/ui")
    print("ui icons:", len(ICONS))
