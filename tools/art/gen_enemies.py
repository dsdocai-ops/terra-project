"""Base enemies for all six biomes: 48x48 frames, 8 facings x (2 idle + 6 move).

Same sheet layout as the miner (gen_character.py): one row per facing in
Facing.SUFFIXES order, columns 0..1 idle, 2..7 move. Each enemy is one function
that draws itself from a Ctx (facing vectors, bob, leg swing); a variant is a
palette change, not a new drawing.

    py gen_enemies.py <out_dir> [enemy_id ...]
"""
import math
import sys

import palette
from pixel import Canvas, sheet
from gen_character import FRAME, SUFFIX_ANGLES, IDLE_FRAMES, WALK_FRAMES, facing_vectors

R = palette.RAMPS
ramp = palette.ramp_from
HEX = palette.hex_rgb
FEET = (24, 41)


class Ctx:
    def __init__(self, angle, phase, moving):
        self.c = Canvas(FRAME, FRAME)
        self.d, self.s = facing_vectors(angle)
        self.front = self.d[1] > 0.25
        self.back = self.d[1] < -0.25
        self.moving = moving
        self.phase = phase
        self.bob = abs(math.sin(phase)) * 1.6 if moving else (1 if phase > 0.5 else 0)
        self.swing = math.sin(phase) * 3.0 if moving else 0.0
        self.flap = math.sin(phase * 2) if moving else math.sin(phase * math.pi)

    def shadow(self, rx=10, ry=4, y=1):
        self.c.ellipse(FEET[0], FEET[1] + y, rx, ry, palette.SHADOW)

    def eyes(self, cx, cy, color, spread=2.2, forward=2.5, size=1):
        if self.back:
            return
        for sign in (-1, 1):
            x = cx + self.d[0] * forward + self.s[0] * spread * sign
            y = cy + self.d[1] * 0.8 + self.s[1] * spread * 0.4 * sign
            self.c.rect(x, y, x + size - 1, y + size - 1, color)

    def legs(self, pairs, length, color, spread=4.0, foot=None, y0=0):
        for k in range(pairs):
            along = (k - (pairs - 1) / 2.0) * 4.0
            for sign in (-1, 1):
                phase_sign = sign * (1 if k % 2 == 0 else -1)
                lx = FEET[0] + self.s[0] * spread * sign + self.d[0] * (along + self.swing * phase_sign * 0.7)
                ly = FEET[1] + self.s[1] * spread * 0.5 * sign + self.d[1] * (along * 0.5 + self.swing * phase_sign * 0.35) - y0
                self.c.line(lx, ly - length, lx, ly, color)
                if foot:
                    self.c.put(lx + 1, ly, foot)


# --- Collapsed Mines ----------------------------------------------------------

def hollow_miner(x):
    c = x.c
    x.shadow()
    cloth = ramp("#4A4350")
    skin = ramp("#B9B6B0")
    x.legs(1, 5, cloth[3], 3)
    body = (24, 29 - x.bob)
    c.ellipse_shaded(body[0], body[1], 7, 8, cloth)
    c.line(body[0] - 4, body[1] + 2, body[0] + 3, body[1] + 6, cloth[3])
    hand = (body[0] + x.s[0] * 8 + x.d[0] * 2, body[1] + 2)
    c.line(hand[0], hand[1] + 3, hand[0], hand[1] - 13, R["timber"][2])
    for k in range(-3, 4):
        c.put(hand[0] + k, hand[1] - 13 + abs(k) // 2, R["iron"][2])
    head = (24 + x.d[0] * 1.5, 18 - x.bob + x.d[1])
    c.ellipse_shaded(head[0], head[1], 6, 6, skin)
    c.ellipse_shaded(head[0], head[1] - 2.5, 7, 4, ramp("#7A6A3A"))
    c.rect(head[0] - 3, head[1] - 4, head[0] - 2, head[1] - 3, palette.OUTLINE)  # crack in the hat
    x.eyes(head[0], head[1] + 0.5, palette.LANTERN_WARM, 2.2, 2.5, 2)


def rock_tick(x):
    c = x.c
    x.shadow(11, 4)
    x.legs(3, 5, R["rock"][3], 7)
    body = (24, 31 - x.bob * 0.6)
    c.ellipse_shaded(body[0], body[1], 11, 8, R["rock"])
    for k in range(-2, 3):
        c.put(body[0] + k * 3, body[1] - 6 + abs(k), R["rock"][0])
    c.ellipse_shaded(body[0] + x.d[0] * 9, body[1] + x.d[1] * 4, 4, 3.5, R["wall"])
    x.eyes(body[0] + x.d[0] * 9, body[1] + x.d[1] * 4 - 1, R["copper"][0], 1.8, 1.5)


def lantern_wisp(x):
    c = x.c
    x.shadow(7, 3, 2)
    y = 26 - x.bob * 2
    c.ellipse(24, y, 10, 10, (255, 179, 71, 40))
    c.ellipse_shaded(24, y, 6, 7, ramp("#FFB347"))
    c.ellipse(24, y + 1, 3, 4, palette.LANTERN_WARM)
    for dx in (-5, 5):
        c.line(24 + dx, y - 7, 24 + dx, y + 7, R["iron"][2])
    c.rect(20, y - 9, 28, y - 8, R["iron"][1])
    c.rect(20, y + 8, 28, y + 9, R["iron"][2])
    c.line(24, y - 9, 24, y - 12, R["iron"][1])
    x.eyes(24, y, palette.OUTLINE, 2, 1.5)


def dynamite_goblin(x):
    c = x.c
    x.shadow()
    skin = ramp("#6FA84A")
    x.legs(1, 5, skin[2], 3)
    body = (24, 31 - x.bob)
    c.ellipse_shaded(body[0], body[1], 6, 7, ramp("#7A4A2A"))
    head = (24 + x.d[0], 21 - x.bob)
    c.ellipse_shaded(head[0], head[1], 6, 5, skin)
    for sign in (-1, 1):  # big ears
        c.polygon([(head[0] + sign * 5, head[1] - 1), (head[0] + sign * 11, head[1] - 4), (head[0] + sign * 6, head[1] + 2)], skin[1])
    x.eyes(head[0], head[1], palette.WHITE, 2.4, 2.5)
    # Bundle of dynamite in the off hand, fuse lit.
    bx, by = body[0] - x.s[0] * 8, body[1] - 2
    for k in (-2, 0, 2):
        c.rect(bx + k, by - 3, bx + k + 1, by + 3, R["blood"][1])
    c.rect(bx - 2, by, bx + 3, by, R["iron"][2])
    c.line(bx, by - 3, bx + 1, by - 6, R["timber"][0])
    c.put(bx + 1, by - 7, palette.LANTERN_WARM)


def cave_bat(c, cx, cy, flap, scale=1.0):
    c.ellipse(cx, cy, 2.5 * scale, 2 * scale, ramp("#4A3A52")[1])
    wing = 5 * scale
    up = -3 * flap
    for sign in (-1, 1):
        c.polygon([(cx + sign * 2, cy), (cx + sign * wing, cy + up - 1), (cx + sign * (wing - 1), cy + 3), (cx + sign * 2, cy + 2)], ramp("#4A3A52")[2])
    c.put(cx - 1, cy - 1, R["blood"][0]); c.put(cx + 1, cy - 1, R["blood"][0])


def cave_bat_swarm(x):
    x.shadow(10, 3, 3)
    for i, (dx, dy) in enumerate(((-8, 2), (6, -3), (-1, 9))):
        cave_bat(x.c, 24 + dx, 24 + dy - x.bob + math.sin(x.phase + i) * 2, math.sin(x.phase * 2 + i * 2), 1.1)


# --- Fungal Caverns -----------------------------------------------------------

def shroomling(x):
    c = x.c
    x.shadow()
    stem = ramp("#E8DCC8")
    x.legs(1, 5, stem[2], 3)
    c.ellipse_shaded(24, 29 - x.bob, 5, 7, stem)
    cap = ramp("#9B5DE5")
    c.ellipse_shaded(24, 20 - x.bob, 12, 8, cap)
    for dx, dy in ((-6, -1), (3, -4), (7, 1), (-1, 2)):
        c.rect(24 + dx, 20 - x.bob + dy, 24 + dx + 1, 20 - x.bob + dy + 1, palette.mix(cap[0], palette.WHITE, 0.5))
    x.eyes(24, 28 - x.bob, palette.OUTLINE, 2, 2)


def spore_spitter(x):
    c = x.c
    x.shadow(9, 3)
    c.rect(22, 30, 25, 41, ramp("#3F7A52")[2])
    for dx in (-5, 5):
        c.polygon([(24, 38), (24 + dx * 2, 32), (24 + dx, 41)], ramp("#3F7A52")[1])
    head = (24 + x.d[0] * 2, 22 - x.bob + x.d[1])
    c.ellipse_shaded(head[0], head[1], 9, 8, ramp("#5EA05A"))
    c.ellipse(head[0] + x.d[0] * 4, head[1] + x.d[1] * 2, 4, 3, palette.OUTLINE)
    c.put(head[0] + x.d[0] * 4, head[1] + x.d[1] * 2, ramp("#7AC943")[0])
    for dx, dy in ((-5, -4), (4, -5), (7, 1)):
        c.put(head[0] + dx, head[1] + dy, accent_hex("#7AC943"))


def accent_hex(h):
    return HEX(h)


def mycel_brute(x):
    c = x.c
    x.shadow(13, 5)
    x.legs(1, 6, ramp("#6B5A4A")[2], 5)
    body = (24, 27 - x.bob)
    c.ellipse_shaded(body[0], body[1], 12, 11, ramp("#6B5A4A"))
    c.ellipse_shaded(body[0], body[1] - 11, 14, 7, ramp("#9B5DE5"))
    for sign in (-1, 1):
        fx = body[0] + x.s[0] * 14 * sign + x.d[0] * x.swing * sign * 0.4
        c.ellipse_shaded(fx, body[1] + 4, 4.5, 4.5, ramp("#6B5A4A"))
    c.put(body[0] - 6, body[1] - 11, palette.mix(HEX("#9B5DE5"), palette.WHITE, 0.5))
    x.eyes(body[0], body[1] - 2, HEX("#5EF2E0"), 3.5, 3, 2)


def glow_moth(x):
    c = x.c
    x.shadow(8, 3, 3)
    y = 26 - x.bob * 2
    wing = 4 + 5 * abs(x.flap)
    for sign in (-1, 1):
        c.polygon([(24 + sign * 2, y), (24 + sign * (wing + 5), y - 6 - 2 * x.flap), (24 + sign * (wing + 3), y + 6), (24 + sign * 2, y + 3)], ramp("#5EF2E0")[2])
        c.put(24 + sign * (wing + 1), y - 1, ramp("#5EF2E0")[0])
    c.ellipse_shaded(24, y + 1, 3, 6, ramp("#B7B2B8"))
    c.ellipse(24, y - 6, 2.5, 2.5, ramp("#B7B2B8")[1])
    for sign in (-1, 1):
        c.line(24 + sign, y - 8, 24 + sign * 4, y - 12, ramp("#B7B2B8")[2])
    x.eyes(24, y - 6, palette.OUTLINE, 1.6, 1.2)


def root_strangler(x):
    c = x.c
    x.shadow(12, 4)
    c.ellipse_shaded(24, 38, 11, 4, ramp("#4A3626"))
    root = ramp("#6B4A32")
    for i, dx in enumerate((-8, -3, 3, 8)):
        sway = math.sin(x.phase + i) * 2
        pts = [(24 + dx, 38), (24 + dx * 1.2 + sway, 30), (24 + dx * 0.8 + sway * 1.5, 22 - (i % 2) * 4), (24 + dx + sway * 2, 14 - (i % 2) * 3)]
        for a, b in zip(pts, pts[1:]):
            c.line(a[0], a[1], b[0], b[1], root[1])
            c.line(a[0] + 1, a[1], b[0] + 1, b[1], root[2])
        c.put(pts[-1][0], pts[-1][1], accent_hex("#7AC943"))


# --- Crystal Hollows ----------------------------------------------------------

def shard_golem(x):
    c = x.c
    x.shadow(12, 5)
    cr = ramp("#8CE8FF")
    x.legs(1, 6, ramp("#4A5A78")[2], 5)
    body = (24, 27 - x.bob)
    c.polygon([(body[0] - 10, body[1] + 8), (body[0] - 7, body[1] - 8), (body[0] + 7, body[1] - 8), (body[0] + 10, body[1] + 8)], ramp("#4A5A78")[1])
    c.polygon([(body[0], body[1] - 14), (body[0] + 5, body[1] - 6), (body[0] - 5, body[1] - 6)], cr[1])
    for sx in (-12, 12):
        c.polygon([(body[0] + sx, body[1] - 4), (body[0] + sx * 0.6, body[1] + 6), (body[0] + sx * 1.1, body[1] + 4)], accent_hex("#F28CC9"))
    c.line(body[0] - 5, body[1], body[0] + 5, body[1] + 4, cr[3])
    x.eyes(body[0], body[1] - 4, cr[0], 3, 2.5, 2)


def prism_bat(x):
    c = x.c
    x.shadow(10, 3, 3)
    y = 25 - x.bob * 2
    wing = 5 + 5 * abs(x.flap)
    pr = ramp("#8CE8FF")
    for sign in (-1, 1):
        c.polygon([(24 + sign * 2, y), (24 + sign * (wing + 6), y - 5 * x.flap - 2), (24 + sign * (wing + 3), y + 5), (24 + sign * 2, y + 3)], ramp("#F28CC9")[2])
    c.polygon([(24, y - 6), (28, y), (24, y + 7), (20, y)], pr[1])
    c.polygon([(24, y - 6), (20, y), (24, y)], pr[0])
    x.eyes(24, y - 1, palette.WHITE, 1.6, 1.2)


def geode_turtle(x):
    c = x.c
    x.shadow(13, 5)
    x.legs(2, 4, ramp("#6A6A78")[2], 8)
    shell = ramp("#6A6A78")
    c.ellipse_shaded(24, 29 - x.bob * 0.5, 13, 9, shell)
    c.ellipse(24, 28 - x.bob * 0.5, 8, 5, ramp("#F28CC9")[2])
    for dx, dy in ((-4, 0), (0, -2), (4, 0), (0, 2)):
        c.put(24 + dx, 28 + dy, ramp("#8CE8FF")[0])
    hx, hy = 24 + x.d[0] * 12, 31 + x.d[1] * 6 - x.bob * 0.5
    c.ellipse_shaded(hx, hy, 4, 3.5, ramp("#7A8A68"))
    x.eyes(hx, hy - 0.5, palette.OUTLINE, 1.6, 1.2)


def crystal_mimic(x):
    c = x.c
    x.shadow(13, 5)
    x.legs(1, 5, R["timber"][3], 8)
    y = 26 - x.bob
    c.polygon([(8, y + 4), (24, y + 10), (40, y + 4), (40, y - 8), (24, y - 2), (8, y - 8)], R["timber"][1])
    c.polygon([(8, y + 4), (24, y + 10), (24, y - 2), (8, y - 8)], R["timber"][2])
    c.rect(11, y - 6, 12, y + 4, R["iron"][1])
    for i in range(5):  # teeth
        c.put(14 + i * 4, y - 1, palette.WHITE); c.put(15 + i * 4, y, palette.WHITE)
    c.polygon([(24, y - 13), (28, y - 7), (24, y - 3), (20, y - 7)], ramp("#F28CC9")[1])
    x.eyes(24, y - 5, ramp("#8CE8FF")[0], 3, 3, 2)


# --- Drowned City -------------------------------------------------------------

def deepkin(x):
    c = x.c
    x.shadow()
    skin = ramp("#5FA38A")
    x.legs(1, 5, skin[2], 3)
    body = (24, 29 - x.bob)
    c.ellipse_shaded(body[0], body[1], 6, 8, skin)
    head = (24 + x.d[0] * 1.5, 18 - x.bob + x.d[1])
    c.ellipse_shaded(head[0], head[1], 6, 5.5, skin)
    c.polygon([(head[0] - 1, head[1] - 5), (head[0] + 1, head[1] - 9), (head[0] + 3, head[1] - 4)], skin[2])  # dorsal fin
    x.eyes(head[0], head[1] - 0.5, palette.LANTERN_WARM, 3, 2.5, 2)
    hand = (body[0] + x.s[0] * 8 + x.d[0] * 4, body[1])
    c.line(hand[0] - x.d[0] * 6, hand[1] + 8, hand[0] + x.d[0] * 4, hand[1] - 14, R["timber"][2])
    c.polygon([(hand[0] + x.d[0] * 4 - 1, hand[1] - 14), (hand[0] + x.d[0] * 4 + 1, hand[1] - 14), (hand[0] + x.d[0] * 4, hand[1] - 19)], R["iron"][0])


def eel_lurker(x):
    c = x.c
    x.shadow(12, 4)
    eel = ramp("#2F6A5A")
    pts = []
    for i in range(9):
        t = i / 8.0
        px = 24 - 14 * x.d[0] * (1 - 2 * t) + math.sin(x.phase + t * 5) * 3 * x.s[0]
        py = 36 - 6 * x.d[1] * (1 - 2 * t) - 8 * math.sin(t * math.pi) - x.bob - (3 if i == 8 else 0)
        pts.append((px, py))
    for i, (px, py) in enumerate(pts):
        r = 3.8 - i * 0.25
        c.ellipse_shaded(px, py, r, r, eel)
    hx, hy = pts[-1]
    c.ellipse_shaded(hx, hy - 2, 4, 3.5, eel)
    c.put(hx + x.d[0] * 2, hy - 3, palette.LANTERN_WARM)
    for k in range(3):
        c.put(hx + x.d[0] * 3 + k - 1, hy, palette.WHITE)


def drowned_priest(x):
    c = x.c
    x.shadow()
    robe = ramp("#3A5A7A")
    c.polygon([(15, 42), (19, 22), (29, 22), (33, 42)], robe[1])
    c.polygon([(15, 42), (19, 22), (24, 22), (24, 42)], robe[2])
    c.rect(18, 36, 30, 37, ramp("#E6E1D3")[2])
    head = (24 + x.d[0], 17 - x.bob + x.d[1])
    c.ellipse_shaded(head[0], head[1], 5, 5, ramp("#9CB8A8"))
    c.ellipse(24, 8 - x.bob, 6, 2, palette.mix(HEX("#E6E1D3"), HEX("#FFD23F"), 0.5))  # halo
    c.ellipse(24, 8 - x.bob, 4, 1, palette.CLEAR)
    x.eyes(head[0], head[1], palette.OUTLINE, 2, 2)
    sx = 24 + x.s[0] * 9
    c.line(sx, 40, sx, 14, R["timber"][1])
    c.ellipse(sx, 12, 2.5, 2.5, ramp("#6FA8C9")[0])


def barnacle_crab(x):
    c = x.c
    x.shadow(13, 5)
    shell = ramp("#8A5A4A")
    x.legs(3, 4, shell[2], 9)
    c.ellipse_shaded(24, 31 - x.bob * 0.5, 12, 8, shell)
    for dx, dy in ((-6, -2), (2, -4), (7, 0), (-1, 2), (4, 3)):
        c.ellipse(24 + dx, 31 + dy - x.bob * 0.5, 1.6, 1.6, ramp("#E6E1D3")[1])
    for sign in (-1, 1):
        cx = 24 + x.s[0] * 13 * sign + x.d[0] * 4
        cy = 30 - x.bob * 0.5 + x.s[1] * 6 * sign
        c.ellipse_shaded(cx, cy, 4, 3.5, shell)
        c.line(cx, cy, cx + sign * 2, cy - 4, shell[3])
    x.eyes(24 + x.d[0] * 6, 26 - x.bob * 0.5 + x.d[1] * 3, palette.OUTLINE, 2.4, 1.2)


def siren(x):
    c = x.c
    x.shadow(9, 3)
    tail = ramp("#2F8A8A")
    sway = math.sin(x.phase) * 2
    c.polygon([(18, 41), (21, 28), (27, 28), (30, 41), (24 + sway, 44)], tail[1])
    c.polygon([(18, 41), (21, 28), (24, 28), (24, 43)], tail[2])
    c.ellipse_shaded(24, 24 - x.bob, 5, 6, ramp("#C8DCD8"))
    hair = ramp("#2F8A8A")
    head = (24 + x.d[0], 15 - x.bob)
    c.ellipse_shaded(head[0], head[1], 5, 5, ramp("#C8DCD8"))
    c.polygon([(head[0] - 6, head[1] - 4), (head[0] + 6, head[1] - 4), (head[0] + 7 + sway, head[1] + 12), (head[0] - 7 + sway, head[1] + 12)], hair[1])
    c.ellipse_shaded(head[0], head[1] + 1, 4, 4, ramp("#C8DCD8"))
    x.eyes(head[0], head[1] + 1, HEX("#E6E1D3"), 2, 2.2)
    c.put(head[0] + x.d[0] * 2, head[1] + 3, accent_hex("#F28CC9"))


# --- Ember Forge --------------------------------------------------------------

def forge_imp(x):
    c = x.c
    x.shadow(8, 3)
    skin = ramp("#D83A3A")
    x.legs(1, 5, skin[2], 3)
    body = (24, 31 - x.bob)
    c.ellipse_shaded(body[0], body[1], 5, 6, skin)
    head = (24 + x.d[0], 22 - x.bob)
    c.ellipse_shaded(head[0], head[1], 6, 5, skin)
    for sign in (-1, 1):
        c.polygon([(head[0] + sign * 4, head[1] - 3), (head[0] + sign * 7, head[1] - 9), (head[0] + sign * 2, head[1] - 4)], palette.hex_rgb("#FFD9A0"))
    x.eyes(head[0], head[1], palette.hex_rgb("#FFD23F"), 2.6, 2.5, 2)
    for k in range(3):  # flame tail
        c.put(body[0] - x.d[0] * 6 + k, body[1] + 3 - k * 2, palette.hex_rgb("#FF6A1F"))
    c.put(body[0] - x.d[0] * 6 + 3, body[1] - 3, palette.hex_rgb("#FFD23F"))


def slag_golem(x):
    c = x.c
    x.shadow(14, 5)
    rock = ramp("#3A2E2E")
    x.legs(1, 7, rock[3], 5)
    body = (24, 26 - x.bob)
    c.polygon([(body[0] - 12, body[1] + 10), (body[0] - 9, body[1] - 9), (body[0] + 9, body[1] - 9), (body[0] + 12, body[1] + 10)], rock[1])
    c.polygon([(body[0] - 12, body[1] + 10), (body[0] - 9, body[1] - 9), (body[0], body[1] - 9), (body[0], body[1] + 10)], rock[2])
    lava = HEX("#FF6A1F")
    for dx, dy in ((-4, -4), (0, -1), (3, 3), (-2, 5), (5, -5)):
        c.line(body[0] + dx, body[1] + dy, body[0] + dx + 3, body[1] + dy + 2, lava)
    c.ellipse_shaded(body[0], body[1] - 12, 5, 4, rock)
    x.eyes(body[0], body[1] - 12, HEX("#FFD23F"), 2.4, 2, 2)
    for sign in (-1, 1):
        c.ellipse_shaded(body[0] + sign * 13, body[1] + 2, 4, 6, rock)
    c.put(body[0] + 14, body[1] + 6, lava); c.put(body[0] - 14, body[1] + 6, lava)


def bellows_drone(x):
    c = x.c
    x.shadow(9, 3, 3)
    y = 25 - x.bob * 2
    leather = ramp("#8A5A30")
    c.polygon([(15, y - 6), (33, y - 6), (29, y + 8), (19, y + 8)], leather[1])
    for k in range(3):
        c.line(16 + k, y - 4 + k * 3, 32 - k, y - 4 + k * 3, leather[3])
    c.rect(22, y + 8, 26, y + 10, R["iron"][1])
    nx, ny = 24 + x.d[0] * 8, y + 2 + x.d[1] * 4
    c.line(24, y + 2, nx, ny, R["iron"][1])
    c.put(nx + x.d[0], ny + x.d[1], HEX("#FFD23F"))
    for sign in (-1, 1):  # rotors
        c.line(24 + sign * 8, y - 8, 24 + sign * (8 + 5 * abs(math.cos(x.phase * 3))), y - 8, R["iron"][0])
    x.eyes(24, y - 1, HEX("#FF6A1F"), 3, 2, 2)


def clockwork_sentry(x):
    c = x.c
    x.shadow(11, 4)
    iron = R["iron"]
    c.polygon([(14, 41), (18, 32), (30, 32), (34, 41)], iron[2])
    c.rect(17, 24, 31, 32, iron[1])
    c.rect(17, 24, 31, 25, iron[0])
    gear = (24, 28)
    for a in range(8):
        ang = a * math.pi / 4 + x.phase
        c.put(gear[0] + math.cos(ang) * 4, gear[1] + math.sin(ang) * 3, R["gold"][1])
    c.ellipse(24, 18, 6, 6, iron[1])
    bx, by = 24 + x.d[0] * 9, 18 + x.d[1] * 4
    c.line(24, 18, bx, by, iron[3])
    c.ellipse(bx, by, 2, 2, palette.OUTLINE)
    x.eyes(24, 17, HEX("#FF6A1F"), 3, 2, 1)


def ashen_smith(x):
    c = x.c
    x.shadow(11, 4)
    ash = ramp("#6A6064")
    x.legs(1, 6, ash[3], 4)
    body = (24, 28 - x.bob)
    c.ellipse_shaded(body[0], body[1], 9, 9, ash)
    c.polygon([(18, 22), (30, 22), (29, 38), (19, 38)], ramp("#5A3A2A")[1])  # apron
    head = (24 + x.d[0], 16 - x.bob)
    c.ellipse_shaded(head[0], head[1], 5.5, 5.5, ash)
    x.eyes(head[0], head[1], HEX("#FF6A1F"), 2.4, 2.5, 1)
    hand = (body[0] + x.s[0] * 10, body[1] - 2)
    c.line(hand[0], hand[1] + 6, hand[0], hand[1] - 10, R["timber"][2])
    c.rect(hand[0] - 3, hand[1] - 13, hand[0] + 3, hand[1] - 9, R["iron"][1])
    c.put(hand[0] + 2, hand[1] - 10, HEX("#FF9A4A"))


# --- The Heart ----------------------------------------------------------------

def veinling(x):
    c = x.c
    x.shadow(10, 4)
    flesh = ramp("#8A2B4A")
    pts = []
    for i in range(7):
        t = i / 6.0
        px = 24 + (t - 0.5) * 22 * x.d[0] + math.sin(x.phase + t * 6) * 2.5
        py = 33 + (t - 0.5) * 8 * x.d[1] - math.sin(t * math.pi) * 5 - x.bob * 0.5
        pts.append((px, py))
    for i, (px, py) in enumerate(pts):
        r = 3 + math.sin(i / 6.0 * math.pi) * 2
        c.ellipse_shaded(px, py, r, r, flesh)
    for sign in (-1, 1):
        a = pts[3]
        c.line(a[0], a[1], a[0] + sign * 9, a[1] - 8 + math.sin(x.phase) * 2, palette.hex_rgb("#8A2BE2"))
    x.eyes(pts[-1][0], pts[-1][1] - 1, HEX("#E8DCC8"), 1.6, 1.2)


def heart_guard(x):
    c = x.c
    x.shadow(13, 5)
    flesh = ramp("#5A2A3A")
    bone = ramp("#E8DCC8")
    x.legs(1, 6, flesh[3], 5)
    body = (24, 27 - x.bob)
    c.ellipse_shaded(body[0], body[1], 10, 10, flesh)
    c.polygon([(body[0] - 9, body[1] - 6), (body[0], body[1] - 12), (body[0] + 9, body[1] - 6), (body[0] + 7, body[1] + 4), (body[0] - 7, body[1] + 4)], bone[1])
    for k in range(-1, 2):
        c.line(body[0] + k * 4, body[1] - 8, body[0] + k * 4, body[1] + 2, bone[3])
    c.ellipse_shaded(body[0], body[1] - 13, 5, 4.5, bone)
    x.eyes(body[0], body[1] - 13, HEX("#FF3C6E"), 2.2, 2, 1)
    sx = body[0] + x.s[0] * 12
    c.line(sx, body[1] + 12, sx, body[1] - 14, bone[2])
    c.polygon([(sx - 3, body[1] - 14), (sx + 3, body[1] - 14), (sx, body[1] - 20)], bone[0])


def echo(x):
    c = x.c
    ghost = ramp("#8A5AD0")
    x.shadow(9, 3)
    body = (24, 29 - x.bob)
    c.ellipse_shaded(body[0], body[1], 7, 8, ghost)
    head = (24 + x.d[0] * 1.5, 18 - x.bob + x.d[1])
    c.ellipse_shaded(head[0], head[1], 6, 6, ramp("#C8A8FF"))
    c.ellipse_shaded(head[0], head[1] - 2.5, 7, 4, ghost)
    x.eyes(head[0], head[1] + 0.5, palette.WHITE, 2.2, 2.5, 2)
    for k in range(4):  # trailing wisps instead of legs
        c.put(24 - 4 + k * 3, 38 + (k % 2) - x.bob * 0.3, ghost[2])
        c.put(24 - 4 + k * 3, 40 + (k % 2), ghost[3])


ENEMIES = {
    "hollow_miner": hollow_miner, "rock_tick": rock_tick, "lantern_wisp": lantern_wisp,
    "dynamite_goblin": dynamite_goblin, "cave_bat_swarm": cave_bat_swarm,
    "shroomling": shroomling, "spore_spitter": spore_spitter, "mycel_brute": mycel_brute,
    "glow_moth": glow_moth, "root_strangler": root_strangler,
    "shard_golem": shard_golem, "prism_bat": prism_bat, "geode_turtle": geode_turtle,
    "crystal_mimic": crystal_mimic,
    "deepkin": deepkin, "eel_lurker": eel_lurker, "drowned_priest": drowned_priest,
    "barnacle_crab": barnacle_crab, "siren": siren,
    "forge_imp": forge_imp, "slag_golem": slag_golem, "bellows_drone": bellows_drone,
    "clockwork_sentry": clockwork_sentry, "ashen_smith": ashen_smith,
    "veinling": veinling, "heart_guard": heart_guard, "echo": echo,
}


def draw_enemy(fn, angle, phase, moving):
    ctx = Ctx(angle, phase, moving)
    fn(ctx)
    ctx.c.outline(palette.OUTLINE)
    return ctx.c


def build(out_dir, enemy_id):
    fn = ENEMIES[enemy_id]
    frames = []
    for angle in SUFFIX_ANGLES:
        for i in range(IDLE_FRAMES):
            frames.append(draw_enemy(fn, angle, i, False))
        for i in range(WALK_FRAMES):
            frames.append(draw_enemy(fn, angle, math.pi * 2 * i / WALK_FRAMES, True))
    out = sheet(frames, IDLE_FRAMES + WALK_FRAMES)
    out.save("%s/enemies/%s_sheet.png" % (out_dir, enemy_id))
    return out


if __name__ == "__main__":
    out = sys.argv[1] if len(sys.argv) > 1 else "../../assets/sprites"
    for name in sys.argv[2:] or list(ENEMIES):
        build(out, name)
        print("enemy:", name)
