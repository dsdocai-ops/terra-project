"""Hollowmere, the town (W5-B7): ground atlas, the pit edge in four stages, 11 buildings
in four states each, and a few props.

Outputs (repo-relative, under the root the caller gives):

    assets/tilesets/town/atlas.png                      floor, fence wall, pit (3 x 64x64, scripts/tiles.gd order)
    assets/tilesets/town/pit_edge_<0..3>.png            256x128, the pit shrinking back as the story advances
    assets/sprites/town/<building>_<state>.png          128x128, state 0 sign / 1 ruined / 2 rebuilt / 3 upgraded
    assets/sprites/town/prop_<name>.png                 lamp post, crate stack, well

State n is the building's level: 0 is the sign on a cleared patch (not built), 1 a ruin
being patched up, 2 rebuilt, 3 upgraded. Buildings sit with their footprint centre on
(64, 96) and their ground contact on the bottom rows, the pivot the Building scene uses.
Colors are palette names: the ground atlas and pit edge from the town biome's own palette,
the buildings and props from palette.MATERIAL.

    python tools/art/gen_town.py
"""

from __future__ import annotations

import math
from collections.abc import Callable
from pathlib import Path

import palette
from gen_tiles import CELL, CY, HALF_H, HALF_W, in_diamond
import gen_tiles
from pixel import Canvas, seeded

REPO_ROOT = Path(__file__).resolve().parents[2]
TILE_DIR = Path("assets/tilesets/town")
SPRITE_DIR = Path("assets/sprites/town")

M = palette.MATERIAL
BUILDING_SIZE = 128
PIT_EDGE_SIZE = (256, 128)
STATES = ("sign", "ruined", "rebuilt", "upgraded")

# Footprint of a building: a diamond centred on (64, 96), 80 wide, 40 tall.
CX, CYB, HW, HH = 64, 96, 40, 20


# --- ground atlas ---------------------------------------------------------

def _town_canvas() -> Canvas:
    return Canvas(CELL, CELL, palette.colors_for("town"))


def floor_tile() -> Canvas:
    """The shared floor with grass tufts and the odd flower on top."""
    c = gen_tiles.floor_tile("town")
    rng = seeded("town_floor")
    for _ in range(9):
        x, y = rng.randint(14, 50), rng.randint(20, 44)
        if in_diamond(x, y, HALF_W, CY, HALF_W - 6, HALF_H - 3) and c.opaque(x, y):
            c.put(x, y, "green_light")
            c.put(x, y - 1, "green_highlight")
    for _ in range(3):
        x, y = rng.randint(16, 48), rng.randint(22, 42)
        if in_diamond(x, y, HALF_W, CY, HALF_W - 8, HALF_H - 4) and c.opaque(x, y):
            c.put(x, y, "town.thatch")
    return c


def atlas() -> Canvas:
    out = Canvas(CELL * 3, CELL, palette.colors_for("town"))
    out.blit(floor_tile(), 0, 0)
    out.blit(gen_tiles.wall_tile("town"), CELL, 0)
    out.blit(gen_tiles.pit_tile("town"), CELL * 2, 0)
    return out


# --- the pit edge ----------------------------------------------------------

# Half-width of the pit's diamond at each story stage (stage 0 is the biggest).
PIT_HALF_WIDTHS = (112, 88, 64, 40)


def pit_edge(stage: int) -> Canvas:
    """The pit and the broken ground around it. Same centre every stage, so a stage
    change reads as the pit closing in."""
    w, h = PIT_EDGE_SIZE
    c = Canvas(w, h, palette.colors_for("town"))
    cx, cy = w / 2, h / 2
    hw = PIT_HALF_WIDTHS[stage]
    hh = hw / 2
    rng = seeded(f"pit_edge_{stage}")
    for y in range(h):
        for x in range(w):
            d = abs(x + 0.5 - cx) / hw + abs(y + 0.5 - cy) / hh
            if d > 1.12:
                continue
            if d <= 0.55:
                c.put(x, y, "outline")
            elif d <= 0.8:
                c.put(x, y, "brown_dark")
            elif d <= 1.0:
                c.put(x, y, "town.wall" if (x + y) % 2 else "brown_dark")
            else:
                c.put(x, y, "brown_base" if rng.random() > 0.2 else "town.wall")
    # Lip: a bright rim along the upper-left edge, where the light hits.
    for y in range(h):
        for x in range(w):
            d = abs(x + 0.5 - cx) / hw + abs(y + 0.5 - cy) / hh
            if 0.97 <= d <= 1.0 and x + 0.5 < cx and y + 0.5 < cy:
                c.put(x, y, "brown_highlight")
    # Rubble on the rim.
    for _ in range(10 + (3 - stage) * 4):
        a = rng.random() * 6.2832
        x = int(cx + math.cos(a) * hw * 1.02)
        y = int(cy + math.sin(a) * hh * 1.02)
        c.rect(x, y, x + 2, y + 1, "brown_light")
    c.outline()
    return c


# --- buildings -------------------------------------------------------------

def _ybase_right(x: float) -> float:
    """Ground line of the right face at column x (the footprint's lower-right edge)."""
    return CYB + HH - (x - CX) * HH / HW


def _ybase_left(x: float) -> float:
    return CYB + HH - (CX - x) * HH / HW


def _box(c: Canvas, h: int, wall: str) -> None:
    """Left and right wall faces of height h over the footprint."""
    mat = M[wall]
    c.polygon([(CX - HW, CYB - h), (CX, CYB + HH - h), (CX, CYB + HH), (CX - HW, CYB)], mat[2])
    c.polygon([(CX, CYB + HH - h), (CX + HW, CYB - h), (CX + HW, CYB), (CX, CYB + HH)], mat[3])
    # Plank / brick lines for texture, lighter on the lit face.
    for k in range(6, h, 7):
        c.line(CX - HW, CYB - k, CX - 1, CYB + HH - k, mat[1])
        c.line(CX + 1, CYB + HH - k, CX + HW, CYB - k, mat[2])


def _roof(c: Canvas, h: int, rise: int, roof: str) -> None:
    """A hipped roof with an overhang over walls of height h."""
    mat = M[roof]
    o = 5  # overhang
    left = (CX - HW - o, CYB - h + 2)
    right = (CX + HW + o, CYB - h + 2)
    front = (CX, CYB + HH - h + o)
    apex = (CX, CYB - HH - h - rise + 8)
    c.polygon([left, front, apex], mat[1])
    c.polygon([front, right, apex], mat[2])
    c.line(left[0], left[1], apex[0], apex[1], mat[0])
    c.line(apex[0], apex[1], right[0], right[1], mat[1])
    c.line(left[0], left[1], front[0], front[1], mat[3])
    c.line(front[0], front[1], right[0], right[1], mat[3])


def _door(c: Canvas, mat: str = "timber") -> None:
    m = M[mat]
    x0, x1 = CX + 10, CX + 22
    c.polygon([(x0, _ybase_right(x0)), (x1, _ybase_right(x1)), (x1, _ybase_right(x1) - 18), (x0, _ybase_right(x0) - 18)], m[3])
    c.polygon([(x0 + 2, _ybase_right(x0 + 2) - 1), (x1 - 2, _ybase_right(x1 - 2) - 1), (x1 - 2, _ybase_right(x1 - 2) - 16), (x0 + 2, _ybase_right(x0 + 2) - 16)], m[1])
    c.put(x1 - 4, _ybase_right(x1 - 4) - 8, M["gold"][1])


def _window(c: Canvas, left_face: bool, lit: bool = True) -> None:
    if left_face:
        x0, x1 = CX - 24, CX - 14
        ya, yb = _ybase_left(x0) - 22, _ybase_left(x1) - 22
    else:
        x0, x1 = CX + 26, CX + 34
        ya, yb = _ybase_right(x0) - 22, _ybase_right(x1) - 22
    glow = M["gold"][0] if lit else M["slate"][1]
    c.polygon([(x0, ya), (x1, yb), (x1, yb + 8), (x0, ya + 8)], glow)
    c.line(x0, ya, x1, yb, M["timber"][3])


def _shadow_patch(c: Canvas, ramp: str = "rock") -> None:
    """The cleared patch of ground a building stands on."""
    c.polygon([(CX - HW - 6, CYB), (CX, CYB - HH - 3), (CX + HW + 6, CYB), (CX, CYB + HH + 3)], M[ramp][1])
    c.polygon([(CX - HW - 2, CYB), (CX, CYB - HH), (CX + HW + 2, CYB), (CX, CYB + HH)], M[ramp][0])


# Per-building identity: wall material, roof ramp, and a feature drawn on top.
def _f_blacksmith(c: Canvas, state: int) -> None:
    c.rect(CX - 34, CYB - 52, CX - 30, CYB - 34, M["iron"][2])  # chimney
    if state >= 2:
        c.rect(CX - 35, CYB - 54, CX - 29, CYB - 52, M["iron"][3])
        c.ellipse(CX - 32, CYB - 62, 3, 2, M["ash"][1])
    c.polygon([(CX - 6, CYB + 17), (CX + 4, CYB + 12), (CX + 10, CYB + 15), (CX, CYB + 20)], M["iron"][1])  # anvil
    c.rect(CX - 1, CYB + 18, CX + 3, CYB + 22, M["iron"][3])


def _f_alchemist(c: Canvas, state: int) -> None:
    c.ellipse(CX + 28, CYB + 12, 6, 6, M["echo"][1])  # flask
    c.rect(CX + 26, CYB + 3, CX + 30, CYB + 7, M["echo"][2])


def _f_map_room(c: Canvas, state: int) -> None:
    c.rect(CX - 1, CYB - 70, CX, CYB - 50, M["timber"][3])  # flag pole
    c.polygon([(CX, CYB - 70), (CX + 14, CYB - 65), (CX, CYB - 60)], M["relic"][1])


def _f_shrine(c: Canvas, state: int) -> None:
    c.polygon([(CX, CYB - 82), (CX + 8, CYB - 66), (CX, CYB - 50), (CX - 8, CYB - 66)], M["echo"][1])
    c.polygon([(CX, CYB - 82), (CX - 8, CYB - 66), (CX, CYB - 64)], M["echo"][0])
    c.put(CX - 3, CYB - 72, "hit_flash")


def _f_tavern(c: Canvas, state: int) -> None:
    c.rect(CX + 30, CYB - 40, CX + 40, CYB - 30, M["timber"][2])  # hanging sign
    c.rect(CX + 33, CYB - 38, CX + 37, CYB - 33, M["gold"][1])
    c.line(CX + 28, CYB - 44, CX + 35, CYB - 40, M["iron"][1])


def _f_relic_vault(c: Canvas, state: int) -> None:
    c.rect(CX + 12, CYB - 24, CX + 20, CYB - 8, M["gold"][2])  # banded vault door


def _f_rune_library(c: Canvas, state: int) -> None:
    c.rect(CX - 26, CYB - 40, CX - 18, CYB - 36, M["relic"][2])  # book stack
    c.rect(CX - 25, CYB - 44, CX - 19, CYB - 40, M["echo"][2])


def _f_training(c: Canvas, state: int) -> None:
    c.rect(CX + 34, CYB + 4, CX + 36, CYB + 22, M["timber"][3])  # dummy post
    c.ellipse(CX + 35, CYB + 2, 4, 4, M["cloth"][0])
    c.line(CX + 30, CYB + 10, CX + 40, CYB + 10, M["timber"][2])


def _f_rescue_camp(c: Canvas, state: int) -> None:
    c.polygon([(CX - 20, CYB - 6), (CX - 10, CYB - 30), (CX, CYB - 6)], M["cloth"][0])  # tent flap
    c.polygon([(CX - 10, CYB - 30), (CX, CYB - 6), (CX + 8, CYB - 10)], M["cloth"][2])


def _f_bounty(c: Canvas, state: int) -> None:
    c.rect(CX - 14, CYB - 40, CX + 14, CYB - 16, M["timber"][2])
    for i, x in enumerate((CX - 10, CX - 2, CX + 6)):
        c.rect(x, CYB - 36 + i, x + 5, CYB - 28 + i, M["bone"][0])


def _f_wardrobe(c: Canvas, state: int) -> None:
    for i, ramp in enumerate(("cloth", "blood", "relic")):
        c.rect(CX - 24 + i * 7, CYB - 38, CX - 19 + i * 7, CYB - 22, M[ramp][1])


# id -> (wall material, roof ramp, feature)
BUILDINGS: dict[str, tuple[str, str, Callable[[Canvas, int], None]]] = {
    "blacksmith": ("rock", "iron", _f_blacksmith),
    "alchemist": ("timber", "echo", _f_alchemist),
    "map_room": ("timber", "relic", _f_map_room),
    "shrine_of_echoes": ("slate", "echo", _f_shrine),
    "tavern": ("timber", "blood", _f_tavern),
    "relic_vault": ("slate", "gold", _f_relic_vault),
    "rune_library": ("timber", "relic", _f_rune_library),
    "training_grounds": ("timber", "copper", _f_training),
    "rescue_camp": ("timber", "cloth", _f_rescue_camp),
    "bounty_board": ("timber", "timber", _f_bounty),
    "wardrobe": ("timber", "hat", _f_wardrobe),
}


def _sign(c: Canvas, name: str) -> None:
    """State 0: a cleared patch, a stake and a board. The board carries a pip in
    the building's roof colour so signs are told apart at a glance."""
    _shadow_patch(c)
    rng = seeded("sign_" + name)
    for _ in range(5):
        x, y = rng.randint(CX - 30, CX + 30), rng.randint(CYB - 8, CYB + 12)
        c.rect(x, y, x + 3, y + 1, M["rock"][2])
    c.rect(CX - 1, CYB - 26, CX + 1, CYB + 4, M["timber"][3])
    c.rect(CX - 12, CYB - 34, CX + 12, CYB - 20, M["timber"][1])
    c.rect(CX - 12, CYB - 34, CX + 12, CYB - 33, M["timber"][0])
    c.rect(CX - 12, CYB - 21, CX + 12, CYB - 20, M["timber"][3])
    roof = BUILDINGS[name][1]
    c.rect(CX - 4, CYB - 30, CX + 4, CYB - 24, M[roof][1])


def _ruin(c: Canvas, name: str) -> None:
    wall, _, _ = BUILDINGS[name]
    rng = seeded("ruin_" + name)
    _shadow_patch(c)
    _box(c, 16, wall)
    # Knock notches out of the wall top.
    for _ in range(7):
        x = rng.randint(CX - HW, CX + HW - 4)
        yb = (_ybase_left(x) if x < CX else _ybase_right(x)) - 16
        c.rect(x, int(yb) - 1, x + rng.randint(3, 6), int(yb) + 3, None)
    # Two standing posts and a fallen beam.
    c.rect(CX - 30, CYB - 30, CX - 27, CYB - 6, M["timber"][3])
    c.rect(CX + 26, CYB - 24, CX + 29, CYB, M["timber"][2])
    c.line(CX - 10, CYB + 18, CX + 14, CYB + 8, M["timber"][2])
    for _ in range(8):
        x, y = rng.randint(CX - 36, CX + 36), rng.randint(CYB + 4, CYB + 22)
        c.rect(x, y, x + 3, y + 1, M["rock"][1])
    c.outline()


def _rebuilt(c: Canvas, name: str, upgraded: bool) -> None:
    wall, roof, feature = BUILDINGS[name]
    height = 38 if upgraded else 30
    _shadow_patch(c)
    if upgraded:
        # Stone footing and a taller roof on top of the same walls.
        c.polygon([(CX - HW - 3, CYB - 4), (CX, CYB + HH - 1), (CX, CYB + HH + 3), (CX - HW - 3, CYB)], M["rock"][2])
        c.polygon([(CX, CYB + HH - 1), (CX + HW + 3, CYB - 4), (CX + HW + 3, CYB), (CX, CYB + HH + 3)], M["rock"][3])
    _box(c, height, wall)
    _door(c)
    _window(c, True, lit=upgraded)
    _window(c, False, lit=upgraded)
    _roof(c, height, 26 if upgraded else 18, roof)
    feature(c, 3 if upgraded else 2)
    if upgraded:
        # A lantern beside the door says "upgraded" from across the square.
        c.rect(CX + 3, CYB + 10, CX + 4, CYB + 20, M["iron"][2])
        c.rect(CX + 1, CYB + 6, CX + 6, CYB + 10, M["gold"][0])
    c.outline()


def building(name: str, state: int) -> Canvas:
    c = Canvas(BUILDING_SIZE, BUILDING_SIZE)
    if state == 0:
        _sign(c, name)
        c.outline()
    elif state == 1:
        _ruin(c, name)
    else:
        _rebuilt(c, name, upgraded=state == 3)
    return c


# --- props ------------------------------------------------------------------

def lamp_post() -> Canvas:
    c = Canvas(16, 40)
    c.rect(7, 12, 8, 38, M["iron"][2])
    c.rect(4, 4, 11, 12, M["gold"][0])
    c.rect(5, 5, 10, 11, M["gold"][1])
    c.rect(3, 2, 12, 4, M["iron"][1])
    c.rect(5, 36, 10, 38, M["iron"][3])
    c.outline()
    return c


def crate_stack() -> Canvas:
    c = Canvas(32, 32)
    c.polygon([(2, 20), (16, 27), (16, 31), (2, 24)], M["timber"][2])
    c.polygon([(16, 27), (30, 20), (30, 24), (16, 31)], M["timber"][3])
    c.polygon([(2, 20), (16, 13), (30, 20), (16, 27)], M["timber"][0])
    c.polygon([(8, 12), (16, 8), (24, 12), (16, 16)], M["timber"][1])
    c.line(2, 22, 16, 29, M["iron"][2])
    c.outline()
    return c


def well() -> Canvas:
    c = Canvas(32, 40)
    c.ellipse_shaded(16, 28, 13, 8, M["rock"])
    c.ellipse(16, 25, 9, 5, M["slate"][3])
    c.rect(5, 8, 7, 26, M["timber"][2])
    c.rect(25, 8, 27, 26, M["timber"][3])
    c.rect(4, 6, 28, 9, M["hat"][1])
    c.line(16, 9, 16, 22, M["copper"][2])
    c.outline()
    return c


PROPS: dict[str, Callable[[], Canvas]] = {
    "lamp_post": lamp_post,
    "crate_stack": crate_stack,
    "well": well,
}


# --- build -------------------------------------------------------------------

def build_tiles(root: Path) -> None:
    root = Path(root)
    atlas().save(root / TILE_DIR / "atlas.png")
    for stage in range(len(PIT_HALF_WIDTHS)):
        pit_edge(stage).save(root / TILE_DIR / f"pit_edge_{stage}.png")


def build_buildings(root: Path) -> None:
    root = Path(root)
    for name in BUILDINGS:
        for state, label in enumerate(STATES):
            building(name, state).save(root / SPRITE_DIR / f"{name}_{label}.png")
    for name, fn in PROPS.items():
        fn().save(root / SPRITE_DIR / f"prop_{name}.png")


def build(root: Path) -> None:
    build_tiles(root)
    build_buildings(root)


if __name__ == "__main__":
    build(REPO_ROOT)
    print("town: atlas, pit edge x4, buildings x44, props x3")
