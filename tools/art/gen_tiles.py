"""Biome tilesets: floor, wall block and pit, 64x64 cells, one atlas per biome.

The ground diamond is 64x32 and sits in rows 16..47 of its cell, so the cell's
centre is the tile origin and a wall can rise 16px above it. Atlas columns match
scripts/tiles.gd: FLOOR (0,0), WALL (1,0), PIT (2,0).

Every color is a name from the biome's own palette (palette.biome(id).names
plus the global set): the ground and wall ramps, the two accents and the light.
A tile that reaches for a color outside its biome fails here with KeyError and
in build_all.py --check.

    python tools/art/gen_tiles.py [biome ...]      (no biome = the six pit biomes)
"""

from __future__ import annotations

import sys
from pathlib import Path
from random import Random

import palette
from pixel import Canvas, seeded

REPO_ROOT = Path(__file__).resolve().parents[2]
OUT_DIR = Path("assets/tilesets")

# Pit biomes in floor order; town gets its own generator (gen_town.py, week 5).
# Biomes with a v2 recipe (gen_tiles_v2.py, art direction v2) are drawn there.
V2_BIOMES: tuple[str, ...] = ("collapsed_mines",)
BIOMES: tuple[str, ...] = tuple(b for b in palette.BIOME_IDS if b != "town" and b not in V2_BIOMES)

CELL = 64
HALF_W = 32
HALF_H = 16
CY = 32  # ground diamond centre row inside the cell
RISE = 16


def in_diamond(x: float, y: float, cx: float, cy: float, hw: float, hh: float) -> bool:
    return abs(x + 0.5 - cx) / hw + abs(y + 0.5 - cy) / hh <= 1.0


def edge_dist(x: float, y: float, cx: float, cy: float, hw: float, hh: float) -> float:
    """0 at the rim, 1 at the centre."""
    return 1.0 - (abs(x + 0.5 - cx) / hw + abs(y + 0.5 - cy) / hh)


def canvas(biome: str) -> Canvas:
    return Canvas(CELL, CELL, palette.colors_for(biome))


# --- floor ------------------------------------------------------------------

def floor_tile(biome: str) -> Canvas:
    c = canvas(biome)
    b = palette.biome(biome)
    rng = seeded("floor" + biome)
    rock = b.ground_ramp
    for y in range(CELL):
        for x in range(CELL):
            if not in_diamond(x, y, HALF_W, CY, HALF_W, HALF_H):
                continue
            d = edge_dist(x, y, HALF_W, CY, HALF_W, HALF_H)
            roll = rng.random()
            color = rock[1]
            if roll < 0.05:
                color = rock[0]
            elif roll > 0.90:
                color = rock[2]
            if d < 0.10:
                color = rock[0] if y + 0.5 < CY else rock[3]
            c.put(x, y, color)
    decorate_floor(c, b, rng)
    return c


def scatter(c: Canvas, rng: Random, count: int, box: tuple[int, int, int, int], fn) -> None:
    """Calls fn(x, y) at `count` random points that sit inside the diamond."""
    placed = 0
    attempts = 0
    while placed < count and attempts < count * 20:
        attempts += 1
        x = rng.randint(box[0], box[2])
        y = rng.randint(box[1], box[3])
        if in_diamond(x, y, HALF_W, CY, HALF_W - 7, HALF_H - 3):
            fn(x, y)
            placed += 1


def decorate_floor(c: Canvas, b: palette.BiomePalette, rng: Random) -> None:
    box = (12, 22, 52, 42)
    rock = b.ground_ramp
    a1, a2, light = b.accent_1_ref, b.accent_2_ref, b.light_ref
    if b.id == "collapsed_mines":
        def pebble(x: int, y: int) -> None:
            c.put(x, y, rock[0])
            c.put(x + 1, y, rock[0])
            c.put(x, y + 1, rock[3])
        scatter(c, rng, 7, box, pebble)
        for _ in range(2):
            px, py = rng.randint(18, 44), rng.randint(26, 38)
            for step in range(rng.randint(3, 6)):
                if in_diamond(px + step, py + step // 2, HALF_W, CY, HALF_W - 4, HALF_H - 2):
                    c.put(px + step, py + step // 2, rock[3])
    elif b.id == "fungal_caverns":
        moss = "green_dark"
        def patch(x: int, y: int) -> None:
            for dx, dy in ((0, 0), (1, 0), (-1, 0), (0, 1), (2, 1)):
                c.put(x + dx, y + dy, moss)
        scatter(c, rng, 6, box, patch)
        def spore(x: int, y: int) -> None:
            c.put(x, y, a2)
        scatter(c, rng, 6, box, spore)
        def shroom(x: int, y: int) -> None:
            c.put(x, y - 1, a1)
            c.put(x + 1, y - 1, a1)
            c.put(x, y, rock[3])
        scatter(c, rng, 3, box, shroom)
    elif b.id == "crystal_hollows":
        def shard(x: int, y: int) -> None:
            col = a1 if rng.random() < 0.5 else a2
            c.put(x, y - 2, col)
            c.put(x, y - 1, col)
            c.put(x, y, col)
            c.put(x - 1, y, light)
            c.put(x + 1, y, "blue_dark")
        scatter(c, rng, 5, box, shard)
        def glint(x: int, y: int) -> None:
            c.put(x, y, "hit_flash")
        scatter(c, rng, 4, box, glint)
    elif b.id == "drowned_city":
        # Cobbles: dark mortar lines along both iso axes.
        for k in range(-3, 4):
            for t in range(0, 64):
                x = t
                y = CY + k * 6 + (t - HALF_W) // 2
                if in_diamond(x, y, HALF_W, CY, HALF_W - 2, HALF_H - 1) and (t % 8 != 0):
                    c.put(x, y, rock[3])
                y2 = CY + k * 6 - (t - HALF_W) // 2
                if in_diamond(x, y2, HALF_W, CY, HALF_W - 2, HALF_H - 1) and (t % 8 != 4):
                    c.put(x, y2, rock[3])
        def weed(x: int, y: int) -> None:
            c.put(x, y, a1)
            c.put(x + 1, y, a1)
            c.put(x, y - 1, a1)
        scatter(c, rng, 5, box, weed)
        def drop(x: int, y: int) -> None:
            c.put(x, y, a2)
        scatter(c, rng, 3, box, drop)
    elif b.id == "ember_forge":
        # Riveted plates and a jagged lava crack.
        for corner in ((22, 32), (42, 32), (32, 26), (32, 38)):
            c.put(corner[0], corner[1], rock[0])
        px, py = 20, 33
        for step in range(22):
            px += 1
            py += rng.choice((-1, 0, 0, 1))
            if in_diamond(px, py, HALF_W, CY, HALF_W - 3, HALF_H - 2):
                c.put(px, py, a1)
                if step % 4 == 0:
                    c.put(px, py + 1, a2)
    elif b.id == "the_heart":
        for _ in range(3):
            px, py = rng.randint(16, 40), rng.randint(26, 38)
            for step in range(rng.randint(5, 9)):
                px += 1
                py += rng.choice((-1, 0, 1))
                if in_diamond(px, py, HALF_W, CY, HALF_W - 4, HALF_H - 2):
                    c.put(px, py, a1)
        def pulse(x: int, y: int) -> None:
            c.put(x, y, light)
            c.put(x + 1, y, "red_base")
        scatter(c, rng, 3, box, pulse)
        def knob(x: int, y: int) -> None:
            c.put(x, y, a2)
        scatter(c, rng, 3, box, knob)


# --- wall -------------------------------------------------------------------

def wall_tile(biome: str) -> Canvas:
    c = canvas(biome)
    b = palette.biome(biome)
    rng = seeded("wall" + biome)
    wall = b.wall_ramp
    top_cy = CY - RISE
    for y in range(CELL):
        for x in range(CELL):
            if in_diamond(x, y, HALF_W, top_cy, HALF_W, HALF_H):
                d = edge_dist(x, y, HALF_W, top_cy, HALF_W, HALF_H)
                roll = rng.random()
                color = wall[0] if roll < 0.05 else (wall[2] if roll > 0.85 else wall[1])
                if d < 0.09:
                    color = wall[0] if y + 0.5 < top_cy else wall[1]
                c.put(x, y, color)
    left = [(0, top_cy), (HALF_W, top_cy + HALF_H), (HALF_W, top_cy + HALF_H + RISE), (0, top_cy + RISE)]
    right = [(HALF_W, top_cy + HALF_H), (CELL, top_cy), (CELL, top_cy + RISE), (HALF_W, top_cy + HALF_H + RISE)]
    c.polygon(left, wall[1])
    c.polygon(right, wall[2])
    for row in (4, 9, 13):
        for x in range(0, HALF_W):
            if rng.random() < 0.85:
                c.put(x, top_cy + int(x / 2) + row, wall[3])
        for x in range(HALF_W, CELL):
            if rng.random() < 0.85:
                c.put(x, top_cy + HALF_H - int((x - HALF_W) / 2) + row, wall[3])
    for _ in range(14):
        x = rng.randint(2, HALF_W - 2)
        c.put(x, top_cy + int(x / 2) + rng.randint(1, RISE - 2), wall[1])
    decorate_wall(c, b, rng, top_cy)
    for y in range(top_cy + HALF_H, top_cy + HALF_H + RISE):
        c.put(HALF_W - 1, y, wall[3])
        c.put(HALF_W, y, wall[3])
    c.outline()
    return c


def left_y(x: int, top_cy: int, offset: int) -> int:
    return top_cy + int(x / 2) + offset


def right_y(x: int, top_cy: int, offset: int) -> int:
    return top_cy + HALF_H - int((x - HALF_W) / 2) + offset


def decorate_wall(c: Canvas, b: palette.BiomePalette, rng: Random, top_cy: int) -> None:
    wall = b.wall_ramp
    a1, a2 = b.accent_1_ref, b.accent_2_ref
    if b.id == "collapsed_mines":
        timber = palette.MATERIAL["timber"]
        for i in range(12):
            c.put(44 + i // 3, top_cy + HALF_H - 8 + i // 2, timber[2])
    elif b.id == "fungal_caverns":
        for _ in range(5):
            x = rng.randint(3, 28)
            y = left_y(x, top_cy, rng.randint(3, 12))
            c.put(x, y, a1)
            c.put(x + 1, y, a1)
            c.put(x, y + 1, "violet_dark")
        for _ in range(4):
            x = rng.randint(36, 60)
            c.put(x, right_y(x, top_cy, rng.randint(3, 12)), a2)
    elif b.id == "crystal_hollows":
        for _ in range(4):
            x = rng.randint(4, 28)
            y = left_y(x, top_cy, rng.randint(3, 11))
            col = a1 if rng.random() < 0.5 else a2
            c.put(x, y, col)
            c.put(x, y - 1, col)
            c.put(x + 1, y, b.light_ref)
        for _ in range(3):
            x = rng.randint(38, 60)
            c.put(x, right_y(x, top_cy, rng.randint(3, 11)), a2)
    elif b.id == "drowned_city":
        for x in range(2, 30, 6):
            for r in (6, 11):
                c.put(x, left_y(x, top_cy, r), wall[3])
                c.put(x + 1, left_y(x + 1, top_cy, r), wall[3])
        for _ in range(6):
            x = rng.randint(2, 28)
            c.put(x, left_y(x, top_cy, rng.randint(10, 14)), a1)
        for _ in range(3):
            x = rng.randint(36, 60)
            c.put(x, right_y(x, top_cy, rng.randint(2, 6)), a2)
    elif b.id == "ember_forge":
        for x in range(3, 30, 5):
            c.put(x, left_y(x, top_cy, 3), wall[0])
            c.put(x, left_y(x, top_cy, 12), wall[0])
        for _ in range(7):
            x = rng.randint(36, 60)
            y = right_y(x, top_cy, rng.randint(5, 12))
            c.put(x, y, a1)
            if rng.random() < 0.4:
                c.put(x, y + 1, a2)
    elif b.id == "the_heart":
        for _ in range(3):
            x = rng.randint(3, 20)
            for step in range(rng.randint(5, 9)):
                c.put(x + step, left_y(x + step, top_cy, 5 + rng.choice((0, 1, 2))), a1)
        for _ in range(4):
            x = rng.randint(38, 60)
            c.put(x, right_y(x, top_cy, rng.randint(2, 12)), b.light_ref)


# --- pit --------------------------------------------------------------------

def pit_tile(biome: str) -> Canvas:
    c = canvas(biome)
    b = palette.biome(biome)
    rng = seeded("pit" + biome)
    # The pit falls away through the wall ramp: rim at the wall base, then the
    # two darkest steps for the drop.
    rim, mid, deep = b.wall_ramp[1], b.wall_ramp[2], b.wall_ramp[3]
    for y in range(CELL):
        for x in range(CELL):
            if not in_diamond(x, y, HALF_W, CY, HALF_W, HALF_H):
                continue
            d = edge_dist(x, y, HALF_W, CY, HALF_W, HALF_H)
            level = d + ((x % 2) + (y % 2) * 2) / 4.0 * 0.12
            c.put(x, y, rim if level < 0.12 else (mid if level < 0.30 else deep))
    glint = b.accent_2_ref if b.id != "collapsed_mines" else palette.MATERIAL["copper"][2]
    for _ in range(3):
        x, y = rng.randint(22, 42), rng.randint(28, 36)
        if in_diamond(x, y, HALF_W, CY, HALF_W - 14, HALF_H - 7):
            c.put(x, y, glint)
    return c


def atlas(biome: str) -> Canvas:
    out = Canvas(CELL * 3, CELL, palette.colors_for(biome))
    out.blit(floor_tile(biome), 0, 0)
    out.blit(wall_tile(biome), CELL, 0)
    out.blit(pit_tile(biome), CELL * 2, 0)
    return out


def build(root: Path, biome: str) -> Canvas:
    out = atlas(biome)
    out.save(Path(root) / OUT_DIR / biome / "atlas.png")
    return out


if __name__ == "__main__":
    for name in sys.argv[1:] or BIOMES:
        build(REPO_ROOT, name)
        print("tiles:", name)
