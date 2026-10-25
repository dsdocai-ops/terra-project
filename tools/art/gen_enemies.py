"""Base enemies for all six biomes: 48x48 frames, 8 facings x (2 idle + 6 move).

Same sheet layout as the miner (gen_character.py): one row per facing in
Facing.SUFFIXES order, columns 0..1 idle, 2..7 move, every facing drawn (no
mirroring; decision 2026-10-21). Each enemy is one function that draws itself
from a Ctx (facing vectors, bob, leg swing); a variant is a palette change, not a
new drawing.

Colors are palette names: palette.MATERIAL ramps, palette.ramp4 hue ramps and
the owning biome's qualified accents ("fungal_caverns.glow_cyan"). Ground shadows
are the separate shadow sprite, not baked into frames.

    python tools/art/gen_enemies.py [enemy_id ...]
"""

from __future__ import annotations

import math
import sys
from collections.abc import Callable
from pathlib import Path

import palette
from gen_character import FRAME, IDLE_FRAMES, SUFFIX_ANGLES, WALK_FRAMES, facing_vectors
from gen_sprites_v2 import V2_ENEMIES
from pixel import Canvas, sheet

REPO_ROOT = Path(__file__).resolve().parents[2]
OUT_DIR = Path("assets/sprites/enemies")

M = palette.MATERIAL
R4 = palette.ramp4
W = "hit_flash"
FEET = (24, 41)

MINES = palette.biome("collapsed_mines")
FUNGAL = palette.biome("fungal_caverns")
CRYSTAL = palette.biome("crystal_hollows")
DROWNED = palette.biome("drowned_city")
EMBER = palette.biome("ember_forge")
HEART = palette.biome("the_heart")

# Ramps built around a biome accent, light -> dark.
LANTERN = ("yellow_highlight", MINES.accent_2_ref, "orange_light", "orange_base")
SPORE = ("violet_highlight", FUNGAL.accent_1_ref, "violet_base", "violet_dark")
GLOW = (FUNGAL.light_ref, FUNGAL.accent_2_ref, "teal_light", "teal_base")
CRYS = (CRYSTAL.light_ref, CRYSTAL.accent_2_ref, "blue_light", "blue_base")
PINKR = ("red_highlight", CRYSTAL.accent_1_ref, "violet_light", "violet_base")
BONE_H = ("neutral_6", HEART.accent_2_ref, "neutral_5", "neutral_4")
FLESH = ("red_base", "red_dark", "red_shadow", "violet_shadow")


class Ctx:
    def __init__(self, angle: float, phase: float, moving: bool) -> None:
        self.c = Canvas(FRAME, FRAME)
        self.d, self.s = facing_vectors(angle)
        self.front = self.d[1] > 0.25
        self.back = self.d[1] < -0.25
        self.moving = moving
        self.phase = phase
        self.bob = abs(math.sin(phase)) * 1.6 if moving else (1 if phase > 0.5 else 0)
        self.swing = math.sin(phase) * 3.0 if moving else 0.0
        self.flap = math.sin(phase * 2) if moving else math.sin(phase * math.pi)

    def eyes(self, cx: float, cy: float, color: str, spread: float = 2.2, forward: float = 2.5, size: int = 1) -> None:
        if self.back:
            return
        for sign in (-1, 1):
            x = cx + self.d[0] * forward + self.s[0] * spread * sign
            y = cy + self.d[1] * 0.8 + self.s[1] * spread * 0.4 * sign
            self.c.rect(x, y, x + size - 1, y + size - 1, color)

    def legs(self, pairs: int, length: float, color: str, spread: float = 4.0, foot: str | None = None, y0: float = 0) -> None:
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

def hollow_miner(x: Ctx) -> None:
    c = x.c
    cloth = M["slate"]
    skin = M["bone"]
    hat = ("yellow_base", "yellow_dark", "yellow_shadow", "brown_dark")
    x.legs(1, 5, cloth[3], 3)
    body = (24, 29 - x.bob)
    c.ellipse_shaded(body[0], body[1], 7, 8, cloth)
    c.line(body[0] - 4, body[1] + 2, body[0] + 3, body[1] + 6, cloth[3])
    hand = (body[0] + x.s[0] * 8 + x.d[0] * 2, body[1] + 2)
    c.line(hand[0], hand[1] + 3, hand[0], hand[1] - 13, M["timber"][2])
    for k in range(-3, 4):
        c.put(hand[0] + k, hand[1] - 13 + abs(k) // 2, M["iron"][2])
    head = (24 + x.d[0] * 1.5, 18 - x.bob + x.d[1])
    c.ellipse_shaded(head[0], head[1], 6, 6, skin)
    c.ellipse_shaded(head[0], head[1] - 2.5, 7, 4, hat)
    c.rect(head[0] - 3, head[1] - 4, head[0] - 2, head[1] - 3, "outline")  # crack in the hat
    x.eyes(head[0], head[1] + 0.5, MINES.light_ref, 2.2, 2.5, 2)


def rock_tick(x: Ctx) -> None:
    c = x.c
    x.legs(3, 5, M["rock"][3], 7)
    body = (24, 31 - x.bob * 0.6)
    c.ellipse_shaded(body[0], body[1], 11, 8, M["rock"])
    for k in range(-2, 3):
        c.put(body[0] + k * 3, body[1] - 6 + abs(k), M["rock"][0])
    c.ellipse_shaded(body[0] + x.d[0] * 9, body[1] + x.d[1] * 4, 4, 3.5, M["wall"])
    x.eyes(body[0] + x.d[0] * 9, body[1] + x.d[1] * 4 - 1, M["copper"][0], 1.8, 1.5)


def lantern_wisp(x: Ctx) -> None:
    c = x.c
    y = 26 - x.bob * 2
    c.ellipse_shaded(24, y, 6, 7, LANTERN)
    c.ellipse(24, y + 1, 3, 4, MINES.light_ref)
    for dx in (-5, 5):
        c.line(24 + dx, y - 7, 24 + dx, y + 7, M["iron"][2])
    c.rect(20, y - 9, 28, y - 8, M["iron"][1])
    c.rect(20, y + 8, 28, y + 9, M["iron"][2])
    c.line(24, y - 9, 24, y - 12, M["iron"][1])
    x.eyes(24, y, "outline", 2, 1.5)


def dynamite_goblin(x: Ctx) -> None:
    c = x.c
    skin = R4("green")
    x.legs(1, 5, skin[2], 3)
    body = (24, 31 - x.bob)
    c.ellipse_shaded(body[0], body[1], 6, 7, R4("brown"))
    head = (24 + x.d[0], 21 - x.bob)
    c.ellipse_shaded(head[0], head[1], 6, 5, skin)
    for sign in (-1, 1):  # big ears
        c.polygon([(head[0] + sign * 5, head[1] - 1), (head[0] + sign * 11, head[1] - 4), (head[0] + sign * 6, head[1] + 2)], skin[1])
    x.eyes(head[0], head[1], W, 2.4, 2.5)
    # Bundle of dynamite in the off hand, fuse lit.
    bx, by = body[0] - x.s[0] * 8, body[1] - 2
    for k in (-2, 0, 2):
        c.rect(bx + k, by - 3, bx + k + 1, by + 3, M["blood"][1])
    c.rect(bx - 2, by, bx + 3, by, M["iron"][2])
    c.line(bx, by - 3, bx + 1, by - 6, M["timber"][0])
    c.put(bx + 1, by - 7, MINES.light_ref)


def cave_bat(c: Canvas, cx: float, cy: float, flap: float, scale: float = 1.0) -> None:
    bat = ("violet_base", "violet_dark", "violet_shadow", "neutral_0")
    c.ellipse(cx, cy, 2.5 * scale, 2 * scale, bat[1])
    wing = 5 * scale
    up = -3 * flap
    for sign in (-1, 1):
        c.polygon([(cx + sign * 2, cy), (cx + sign * wing, cy + up - 1), (cx + sign * (wing - 1), cy + 3), (cx + sign * 2, cy + 2)], bat[2])
    c.put(cx - 1, cy - 1, M["blood"][0])
    c.put(cx + 1, cy - 1, M["blood"][0])


def cave_bat_swarm(x: Ctx) -> None:
    for i, (dx, dy) in enumerate(((-8, 2), (6, -3), (-1, 9))):
        cave_bat(x.c, 24 + dx, 24 + dy - x.bob + math.sin(x.phase + i) * 2, math.sin(x.phase * 2 + i * 2), 1.1)


# --- Fungal Caverns -----------------------------------------------------------

def shroomling(x: Ctx) -> None:
    c = x.c
    stem = M["bone"]
    x.legs(1, 5, stem[2], 3)
    c.ellipse_shaded(24, 29 - x.bob, 5, 7, stem)
    c.ellipse_shaded(24, 20 - x.bob, 12, 8, SPORE)
    for dx, dy in ((-6, -1), (3, -4), (7, 1), (-1, 2)):
        c.rect(24 + dx, 20 - x.bob + dy, 24 + dx + 1, 20 - x.bob + dy + 1, FUNGAL.light_ref)
    x.eyes(24, 28 - x.bob, "outline", 2, 2)


def spore_spitter(x: Ctx) -> None:
    c = x.c
    stalk = R4("green")
    head_ramp = R4("green", high=True)
    c.rect(22, 30, 25, 41, stalk[2])
    for dx in (-5, 5):
        c.polygon([(24, 38), (24 + dx * 2, 32), (24 + dx, 41)], stalk[1])
    head = (24 + x.d[0] * 2, 22 - x.bob + x.d[1])
    c.ellipse_shaded(head[0], head[1], 9, 8, head_ramp)
    c.ellipse(head[0] + x.d[0] * 4, head[1] + x.d[1] * 2, 4, 3, "outline")
    c.put(head[0] + x.d[0] * 4, head[1] + x.d[1] * 2, head_ramp[0])
    for dx, dy in ((-5, -4), (4, -5), (7, 1)):
        c.put(head[0] + dx, head[1] + dy, "poison")


def mycel_brute(x: Ctx) -> None:
    c = x.c
    hide = R4("brown")
    x.legs(1, 6, hide[2], 5)
    body = (24, 27 - x.bob)
    c.ellipse_shaded(body[0], body[1], 12, 11, hide)
    c.ellipse_shaded(body[0], body[1] - 11, 14, 7, SPORE)
    for sign in (-1, 1):
        fx = body[0] + x.s[0] * 14 * sign + x.d[0] * x.swing * sign * 0.4
        c.ellipse_shaded(fx, body[1] + 4, 4.5, 4.5, hide)
    c.put(body[0] - 6, body[1] - 11, SPORE[0])
    x.eyes(body[0], body[1] - 2, FUNGAL.accent_2_ref, 3.5, 3, 2)


def glow_moth(x: Ctx) -> None:
    c = x.c
    y = 26 - x.bob * 2
    wing = 4 + 5 * abs(x.flap)
    for sign in (-1, 1):
        c.polygon([(24 + sign * 2, y), (24 + sign * (wing + 5), y - 6 - 2 * x.flap), (24 + sign * (wing + 3), y + 6), (24 + sign * 2, y + 3)], GLOW[2])
        c.put(24 + sign * (wing + 1), y - 1, GLOW[0])
    c.ellipse_shaded(24, y + 1, 3, 6, M["iron"])
    c.ellipse(24, y - 6, 2.5, 2.5, M["iron"][1])
    for sign in (-1, 1):
        c.line(24 + sign, y - 8, 24 + sign * 4, y - 12, M["iron"][2])
    x.eyes(24, y - 6, "outline", 1.6, 1.2)


def root_strangler(x: Ctx) -> None:
    c = x.c
    c.ellipse_shaded(24, 38, 11, 4, M["wall"])
    root = M["rock"]
    for i, dx in enumerate((-8, -3, 3, 8)):
        sway = math.sin(x.phase + i) * 2
        pts = [(24 + dx, 38), (24 + dx * 1.2 + sway, 30), (24 + dx * 0.8 + sway * 1.5, 22 - (i % 2) * 4), (24 + dx + sway * 2, 14 - (i % 2) * 3)]
        for a, b in zip(pts, pts[1:]):
            c.line(a[0], a[1], b[0], b[1], root[1])
            c.line(a[0] + 1, a[1], b[0] + 1, b[1], root[2])
        c.put(pts[-1][0], pts[-1][1], "poison")


# --- Crystal Hollows ----------------------------------------------------------

def shard_golem(x: Ctx) -> None:
    c = x.c
    stone = CRYSTAL.ground_ramp
    x.legs(1, 6, stone[2], 5)
    body = (24, 27 - x.bob)
    c.polygon([(body[0] - 10, body[1] + 8), (body[0] - 7, body[1] - 8), (body[0] + 7, body[1] - 8), (body[0] + 10, body[1] + 8)], stone[1])
    c.polygon([(body[0], body[1] - 14), (body[0] + 5, body[1] - 6), (body[0] - 5, body[1] - 6)], CRYS[1])
    for sx in (-12, 12):
        c.polygon([(body[0] + sx, body[1] - 4), (body[0] + sx * 0.6, body[1] + 6), (body[0] + sx * 1.1, body[1] + 4)], CRYSTAL.accent_1_ref)
    c.line(body[0] - 5, body[1], body[0] + 5, body[1] + 4, CRYS[3])
    x.eyes(body[0], body[1] - 4, CRYS[0], 3, 2.5, 2)


def prism_bat(x: Ctx) -> None:
    c = x.c
    y = 25 - x.bob * 2
    wing = 5 + 5 * abs(x.flap)
    for sign in (-1, 1):
        c.polygon([(24 + sign * 2, y), (24 + sign * (wing + 6), y - 5 * x.flap - 2), (24 + sign * (wing + 3), y + 5), (24 + sign * 2, y + 3)], PINKR[2])
    c.polygon([(24, y - 6), (28, y), (24, y + 7), (20, y)], CRYS[1])
    c.polygon([(24, y - 6), (20, y), (24, y)], CRYS[0])
    x.eyes(24, y - 1, W, 1.6, 1.2)


def geode_turtle(x: Ctx) -> None:
    c = x.c
    shell = M["ash"]
    x.legs(2, 4, shell[2], 8)
    c.ellipse_shaded(24, 29 - x.bob * 0.5, 13, 9, shell)
    c.ellipse(24, 28 - x.bob * 0.5, 8, 5, PINKR[2])
    for dx, dy in ((-4, 0), (0, -2), (4, 0), (0, 2)):
        c.put(24 + dx, 28 + dy, CRYS[0])
    hx, hy = 24 + x.d[0] * 12, 31 + x.d[1] * 6 - x.bob * 0.5
    c.ellipse_shaded(hx, hy, 4, 3.5, R4("green"))
    x.eyes(hx, hy - 0.5, "outline", 1.6, 1.2)


def crystal_mimic(x: Ctx) -> None:
    c = x.c
    x.legs(1, 5, M["timber"][3], 8)
    y = 26 - x.bob
    c.polygon([(8, y + 4), (24, y + 10), (40, y + 4), (40, y - 8), (24, y - 2), (8, y - 8)], M["timber"][1])
    c.polygon([(8, y + 4), (24, y + 10), (24, y - 2), (8, y - 8)], M["timber"][2])
    c.rect(11, y - 6, 12, y + 4, M["iron"][1])
    for i in range(5):  # teeth
        c.put(14 + i * 4, y - 1, W)
        c.put(15 + i * 4, y, W)
    c.polygon([(24, y - 13), (28, y - 7), (24, y - 3), (20, y - 7)], PINKR[1])
    x.eyes(24, y - 5, CRYS[0], 3, 3, 2)


# --- Drowned City -------------------------------------------------------------

def deepkin(x: Ctx) -> None:
    c = x.c
    skin = R4("teal", high=True)
    x.legs(1, 5, skin[2], 3)
    body = (24, 29 - x.bob)
    c.ellipse_shaded(body[0], body[1], 6, 8, skin)
    head = (24 + x.d[0] * 1.5, 18 - x.bob + x.d[1])
    c.ellipse_shaded(head[0], head[1], 6, 5.5, skin)
    c.polygon([(head[0] - 1, head[1] - 5), (head[0] + 1, head[1] - 9), (head[0] + 3, head[1] - 4)], skin[2])  # dorsal fin
    x.eyes(head[0], head[1] - 0.5, "yellow_highlight", 3, 2.5, 2)
    hand = (body[0] + x.s[0] * 8 + x.d[0] * 4, body[1])
    c.line(hand[0] - x.d[0] * 6, hand[1] + 8, hand[0] + x.d[0] * 4, hand[1] - 14, M["timber"][2])
    c.polygon([(hand[0] + x.d[0] * 4 - 1, hand[1] - 14), (hand[0] + x.d[0] * 4 + 1, hand[1] - 14), (hand[0] + x.d[0] * 4, hand[1] - 19)], M["iron"][0])


def eel_lurker(x: Ctx) -> None:
    c = x.c
    eel = R4("teal")
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
    c.put(hx + x.d[0] * 2, hy - 3, "yellow_highlight")
    for k in range(3):
        c.put(hx + x.d[0] * 3 + k - 1, hy, W)


def drowned_priest(x: Ctx) -> None:
    c = x.c
    robe = R4("blue")
    c.polygon([(15, 42), (19, 22), (29, 22), (33, 42)], robe[1])
    c.polygon([(15, 42), (19, 22), (24, 22), (24, 42)], robe[2])
    c.rect(18, 36, 30, 37, "neutral_4")
    head = (24 + x.d[0], 17 - x.bob + x.d[1])
    c.ellipse_shaded(head[0], head[1], 5, 5, M["bone"])
    c.ellipse(24, 8 - x.bob, 6, 2, "yellow_light")  # halo
    c.ellipse(24, 8 - x.bob, 4, 1, None)
    x.eyes(head[0], head[1], "outline", 2, 2)
    sx = 24 + x.s[0] * 9
    c.line(sx, 40, sx, 14, M["timber"][1])
    c.ellipse(sx, 12, 2.5, 2.5, "blue_highlight")


def barnacle_crab(x: Ctx) -> None:
    c = x.c
    shell = R4("brown", high=True)
    x.legs(3, 4, shell[2], 9)
    c.ellipse_shaded(24, 31 - x.bob * 0.5, 12, 8, shell)
    for dx, dy in ((-6, -2), (2, -4), (7, 0), (-1, 2), (4, 3)):
        c.ellipse(24 + dx, 31 + dy - x.bob * 0.5, 1.6, 1.6, DROWNED.accent_2_ref)
    for sign in (-1, 1):
        cx = 24 + x.s[0] * 13 * sign + x.d[0] * 4
        cy = 30 - x.bob * 0.5 + x.s[1] * 6 * sign
        c.ellipse_shaded(cx, cy, 4, 3.5, shell)
        c.line(cx, cy, cx + sign * 2, cy - 4, shell[3])
    x.eyes(24 + x.d[0] * 6, 26 - x.bob * 0.5 + x.d[1] * 3, "outline", 2.4, 1.2)


def siren(x: Ctx) -> None:
    c = x.c
    tail = R4("teal", high=True)
    skin = M["bone"]
    sway = math.sin(x.phase) * 2
    c.polygon([(18, 41), (21, 28), (27, 28), (30, 41), (24 + sway, 44)], tail[1])
    c.polygon([(18, 41), (21, 28), (24, 28), (24, 43)], tail[2])
    c.ellipse_shaded(24, 24 - x.bob, 5, 6, skin)
    head = (24 + x.d[0], 15 - x.bob)
    c.ellipse_shaded(head[0], head[1], 5, 5, skin)
    c.polygon([(head[0] - 6, head[1] - 4), (head[0] + 6, head[1] - 4), (head[0] + 7 + sway, head[1] + 12), (head[0] - 7 + sway, head[1] + 12)], tail[1])
    c.ellipse_shaded(head[0], head[1] + 1, 4, 4, skin)
    x.eyes(head[0], head[1] + 1, DROWNED.accent_2_ref, 2, 2.2)
    c.put(head[0] + x.d[0] * 2, head[1] + 3, "red_light")


# --- Ember Forge --------------------------------------------------------------

def forge_imp(x: Ctx) -> None:
    c = x.c
    skin = R4("red")
    x.legs(1, 5, skin[2], 3)
    body = (24, 31 - x.bob)
    c.ellipse_shaded(body[0], body[1], 5, 6, skin)
    head = (24 + x.d[0], 22 - x.bob)
    c.ellipse_shaded(head[0], head[1], 6, 5, skin)
    for sign in (-1, 1):
        c.polygon([(head[0] + sign * 4, head[1] - 3), (head[0] + sign * 7, head[1] - 9), (head[0] + sign * 2, head[1] - 4)], "orange_highlight")
    x.eyes(head[0], head[1], EMBER.accent_2_ref, 2.6, 2.5, 2)
    for k in range(3):  # flame tail
        c.put(body[0] - x.d[0] * 6 + k, body[1] + 3 - k * 2, EMBER.accent_1_ref)
    c.put(body[0] - x.d[0] * 6 + 3, body[1] - 3, EMBER.accent_2_ref)


def slag_golem(x: Ctx) -> None:
    c = x.c
    rock = EMBER.ground_ramp
    x.legs(1, 7, rock[3], 5)
    body = (24, 26 - x.bob)
    c.polygon([(body[0] - 12, body[1] + 10), (body[0] - 9, body[1] - 9), (body[0] + 9, body[1] - 9), (body[0] + 12, body[1] + 10)], rock[1])
    c.polygon([(body[0] - 12, body[1] + 10), (body[0] - 9, body[1] - 9), (body[0], body[1] - 9), (body[0], body[1] + 10)], rock[2])
    lava = EMBER.accent_1_ref
    for dx, dy in ((-4, -4), (0, -1), (3, 3), (-2, 5), (5, -5)):
        c.line(body[0] + dx, body[1] + dy, body[0] + dx + 3, body[1] + dy + 2, lava)
    c.ellipse_shaded(body[0], body[1] - 12, 5, 4, rock)
    x.eyes(body[0], body[1] - 12, EMBER.accent_2_ref, 2.4, 2, 2)
    for sign in (-1, 1):
        c.ellipse_shaded(body[0] + sign * 13, body[1] + 2, 4, 6, rock)
    c.put(body[0] + 14, body[1] + 6, lava)
    c.put(body[0] - 14, body[1] + 6, lava)


def bellows_drone(x: Ctx) -> None:
    c = x.c
    y = 25 - x.bob * 2
    leather = R4("brown", high=True)
    c.polygon([(15, y - 6), (33, y - 6), (29, y + 8), (19, y + 8)], leather[1])
    for k in range(3):
        c.line(16 + k, y - 4 + k * 3, 32 - k, y - 4 + k * 3, leather[3])
    c.rect(22, y + 8, 26, y + 10, M["iron"][1])
    nx, ny = 24 + x.d[0] * 8, y + 2 + x.d[1] * 4
    c.line(24, y + 2, nx, ny, M["iron"][1])
    c.put(nx + x.d[0], ny + x.d[1], EMBER.accent_2_ref)
    for sign in (-1, 1):  # rotors
        c.line(24 + sign * 8, y - 8, 24 + sign * (8 + 5 * abs(math.cos(x.phase * 3))), y - 8, M["iron"][0])
    x.eyes(24, y - 1, EMBER.accent_1_ref, 3, 2, 2)


def clockwork_sentry(x: Ctx) -> None:
    c = x.c
    iron = M["iron"]
    c.polygon([(14, 41), (18, 32), (30, 32), (34, 41)], iron[2])
    c.rect(17, 24, 31, 32, iron[1])
    c.rect(17, 24, 31, 25, iron[0])
    gear = (24, 28)
    for a in range(8):
        ang = a * math.pi / 4 + x.phase
        c.put(gear[0] + math.cos(ang) * 4, gear[1] + math.sin(ang) * 3, M["gold"][1])
    c.ellipse(24, 18, 6, 6, iron[1])
    bx, by = 24 + x.d[0] * 9, 18 + x.d[1] * 4
    c.line(24, 18, bx, by, iron[3])
    c.ellipse(bx, by, 2, 2, "outline")
    x.eyes(24, 17, EMBER.accent_1_ref, 3, 2, 1)


def ashen_smith(x: Ctx) -> None:
    c = x.c
    ash = M["ash"]
    x.legs(1, 6, ash[3], 4)
    body = (24, 28 - x.bob)
    c.ellipse_shaded(body[0], body[1], 9, 9, ash)
    c.polygon([(18, 22), (30, 22), (29, 38), (19, 38)], "brown_dark")  # apron
    head = (24 + x.d[0], 16 - x.bob)
    c.ellipse_shaded(head[0], head[1], 5.5, 5.5, ash)
    x.eyes(head[0], head[1], EMBER.accent_1_ref, 2.4, 2.5, 1)
    hand = (body[0] + x.s[0] * 10, body[1] - 2)
    c.line(hand[0], hand[1] + 6, hand[0], hand[1] - 10, M["timber"][2])
    c.rect(hand[0] - 3, hand[1] - 13, hand[0] + 3, hand[1] - 9, M["iron"][1])
    c.put(hand[0] + 2, hand[1] - 10, EMBER.light_ref)


# --- The Heart ----------------------------------------------------------------

def veinling(x: Ctx) -> None:
    c = x.c
    pts = []
    for i in range(7):
        t = i / 6.0
        px = 24 + (t - 0.5) * 22 * x.d[0] + math.sin(x.phase + t * 6) * 2.5
        py = 33 + (t - 0.5) * 8 * x.d[1] - math.sin(t * math.pi) * 5 - x.bob * 0.5
        pts.append((px, py))
    for i, (px, py) in enumerate(pts):
        r = 3 + math.sin(i / 6.0 * math.pi) * 2
        c.ellipse_shaded(px, py, r, r, FLESH)
    for sign in (-1, 1):
        a = pts[3]
        c.line(a[0], a[1], a[0] + sign * 9, a[1] - 8 + math.sin(x.phase) * 2, HEART.accent_1_ref)
    x.eyes(pts[-1][0], pts[-1][1] - 1, HEART.accent_2_ref, 1.6, 1.2)


def heart_guard(x: Ctx) -> None:
    c = x.c
    flesh = HEART.ground_ramp
    bone = BONE_H
    x.legs(1, 6, flesh[3], 5)
    body = (24, 27 - x.bob)
    c.ellipse_shaded(body[0], body[1], 10, 10, flesh)
    c.polygon([(body[0] - 9, body[1] - 6), (body[0], body[1] - 12), (body[0] + 9, body[1] - 6), (body[0] + 7, body[1] + 4), (body[0] - 7, body[1] + 4)], bone[1])
    for k in range(-1, 2):
        c.line(body[0] + k * 4, body[1] - 8, body[0] + k * 4, body[1] + 2, bone[3])
    c.ellipse_shaded(body[0], body[1] - 13, 5, 4.5, bone)
    x.eyes(body[0], body[1] - 13, HEART.light_ref, 2.2, 2, 1)
    sx = body[0] + x.s[0] * 12
    c.line(sx, body[1] + 12, sx, body[1] - 14, bone[2])
    c.polygon([(sx - 3, body[1] - 14), (sx + 3, body[1] - 14), (sx, body[1] - 20)], bone[0])


def echo(x: Ctx) -> None:
    c = x.c
    ghost = R4("violet", high=True)
    pale = ("neutral_6", "violet_highlight", "violet_light", "violet_base")
    body = (24, 29 - x.bob)
    c.ellipse_shaded(body[0], body[1], 7, 8, ghost)
    head = (24 + x.d[0] * 1.5, 18 - x.bob + x.d[1])
    c.ellipse_shaded(head[0], head[1], 6, 6, pale)
    c.ellipse_shaded(head[0], head[1] - 2.5, 7, 4, ghost)
    x.eyes(head[0], head[1] + 0.5, W, 2.2, 2.5, 2)
    for k in range(4):  # trailing wisps instead of legs
        c.put(24 - 4 + k * 3, 38 + (k % 2) - x.bob * 0.3, ghost[2])
        c.put(24 - 4 + k * 3, 40 + (k % 2), ghost[3])


ENEMIES: dict[str, Callable[[Ctx], None]] = {
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


def draw_enemy(fn: Callable[[Ctx], None], angle: float, phase: float, moving: bool) -> Canvas:
    ctx = Ctx(angle, phase, moving)
    fn(ctx)
    ctx.c.outline()
    return ctx.c


def rows(enemy_id: str) -> list[list[Canvas]]:
    fn = ENEMIES[enemy_id]
    out: list[list[Canvas]] = []
    for angle in SUFFIX_ANGLES:
        row = [draw_enemy(fn, angle, i, False) for i in range(IDLE_FRAMES)]
        row += [draw_enemy(fn, angle, math.pi * 2 * i / WALK_FRAMES, True) for i in range(WALK_FRAMES)]
        out.append(row)
    return out


def build_one(root: Path, enemy_id: str) -> Canvas:
    out = sheet(rows(enemy_id))
    out.save(Path(root) / OUT_DIR / f"{enemy_id}_sheet.png")
    return out


def build(root: Path) -> None:
    """Writes every enemy sheet under root at its repo-relative path, except
    the ids gen_sprites_v2.py draws in the v2 style (art direction v2)."""
    for enemy_id in ENEMIES:
        if enemy_id not in V2_ENEMIES:
            build_one(root, enemy_id)


if __name__ == "__main__":
    for name in sys.argv[1:] or [e for e in ENEMIES if e not in V2_ENEMIES]:
        build_one(REPO_ROOT, name)
        print("enemy:", name)
