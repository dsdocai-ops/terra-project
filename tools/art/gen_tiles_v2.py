"""v2 biome tiles (art direction v2, D1/D2): floor, wall and pit for one biome,
drawn at quarter resolution and shipped 4x.

Each cell is drawn 16x24 and ships 64x96. The ground diamond is drawn 16x8 at
rows 8..15 (ships rows 32..63), so its centre is the cell centre and the
TileSet's default texture origin lines it up with the 64x32 tile. A wall rises
8 drawn px (32 px) above its footprint; its top face fills rows 0..7. Atlas
columns match scripts/tiles.gd: FLOOR (0,0), WALL (1,0), PIT (2,0).

Recipes are ports of the approved mockups (docs/art-direction/v2/mockup-src/
lib2.js: mineTex, stonePx/wallBlk); colors come from palette.v2_colors(biome).

    py tools/art/gen_tiles_v2.py [biome ...]      (no biome = every v2 biome)
"""

from __future__ import annotations

import sys
from pathlib import Path

import palette
import pixel
from gen_tiles import V2_BIOMES
from pixel import Canvas

REPO_ROOT = Path(__file__).resolve().parents[2]
OUT_DIR = Path("assets/tilesets")

SCALE = 4
CELL_W, CELL_H = 16, 24
TOP_X, TOP_Y = 8, 8  # floor diamond top vertex inside a drawn cell
WALL_RISE = 8

# Biomes with a v2 recipe. The rest keep gen_tiles.py until AR-6.
BIOMES: tuple[str, ...] = V2_BIOMES


def _in_diamond(x: int, y: int) -> bool:
    r = y - TOP_Y
    if not 0 <= r < 8:
        return False
    k = r if r < 4 else 7 - r
    w = 2 * k + 2
    return TOP_X - w <= x < TOP_X + w


def _canvas(biome: str) -> Canvas:
    return Canvas(CELL_W, CELL_H, palette.v2_colors(biome))


# --- collapsed_mines ---------------------------------------------------------

def _mine_detail(c: Canvas, x: int, y: int, t: float, n: int) -> None:
    """mineTex from the mockups: pebbles with a lit top, short cracks, rubble
    nubs, rare copper glints, and dust specks."""
    if t < 0.35:
        c.put(x, y, "mine_floor_6")
        c.put(x + 1, y, "mine_floor_6")
        c.put(x, y - 1, "mine_floor_0")
    elif t < 0.45:
        px, py = x, y
        for k in range(4):
            c.put(px, py, "mine_floor_7")
            px += 1
            py += 1 if pixel.hash01(n, k) < 0.5 else 0
    elif t < 0.6:
        c.put(x, y, "mine_floor_6")
        c.put(x - 1, y - 1, "mine_floor_1")
    elif t < 0.63:
        c.put(x, y, "copper_1")
        c.put(x + 1, y, "copper_0")
    else:
        c.put(x, y, "mine_floor_5" if t < 0.8 else "mine_floor_1")


def mines_floor() -> Canvas:
    c = _canvas("collapsed_mines")
    pixel.iso_tile(c, TOP_X, TOP_Y, "mine_floor_3")
    # Two-tone base: a few warmer and darker patches so the tile is not flat.
    for y in range(TOP_Y, TOP_Y + 8):
        for x in range(CELL_W):
            if _in_diamond(x, y):
                v = pixel.hash01(x * 7 + 1, y * 13 + 5)
                if v < 0.12:
                    c.put(x, y, "mine_floor_2")
                elif v > 0.9:
                    c.put(x, y, "mine_floor_4")
    pixel.scatter(c, 28, _mine_detail, seed=31, mask=lambda x, y: _in_diamond(x, y) and _in_diamond(x + 1, y))
    return c


MINE_STONE = {"a": "mine_stone_3", "b": "mine_stone_4", "c": "mine_stone_1", "hi": "mine_stone_0", "lo": "mine_stone_6", "m": "mine_stone_7", "ore": "copper_1"}
MINE_STONE_SHADE = {"a": "mine_stone_shade_3", "b": "mine_stone_shade_4", "c": "mine_stone_shade_1", "hi": "mine_stone_shade_0",
                    "lo": "mine_stone_shade_6", "m": "mine_stone_shade_7", "ore": "copper_3"}


def mines_wall() -> Canvas:
    c = _canvas("collapsed_mines")
    pixel.iso_block(
        c, TOP_X, TOP_Y + 0, WALL_RISE, "mine_stone_5",
        pixel.stone_face(MINE_STONE, seed=3), pixel.stone_face(MINE_STONE_SHADE, seed=6), top_hi="mine_stone_2",
    )
    # Rubble on the cap, as the mockup's wallBlk does.
    for n in range(4):
        x = 4 + int(pixel.hash01(n, 41) * 8)
        y = 2 + int(pixel.hash01(n, 43) * 4)
        c.put(x, y, "mine_stone_6")
    return c


def mines_pit() -> Canvas:
    """A hole in the floor: the far rim shows a rock face dropping into the
    dark, the near rim is a lip of floor."""
    c = _canvas("collapsed_mines")
    pixel.iso_tile(c, TOP_X, TOP_Y, "outline")
    for y in range(TOP_Y, TOP_Y + 8):
        for x in range(CELL_W):
            if not _in_diamond(x, y):
                continue
            r = y - TOP_Y
            if r == 0 or (r == 1 and abs(x - TOP_X + 0.5) > 2):
                c.put(x, y, "mine_floor_6")
            elif r in (1, 2) and abs(x - TOP_X + 0.5) <= 6:
                c.put(x, y, "mine_stone_shade_6" if r == 1 else "mine_stone_shade_7")
            elif r == 3 and abs(x - TOP_X + 0.5) <= 7:
                c.put(x, y, "iron_v2_9")
    return c


RECIPES = {
    "collapsed_mines": (mines_floor, mines_wall, mines_pit),
}


def atlas(biome: str) -> Canvas:
    floor, wall, pit = RECIPES[biome]
    out = Canvas(CELL_W * 3, CELL_H, palette.v2_colors(biome))
    out.blit(floor(), 0, 0)
    out.blit(wall(), CELL_W, 0)
    out.blit(pit(), CELL_W * 2, 0)
    return pixel.export_scaled(out, SCALE)


def build(root: Path, biome: str) -> Canvas:
    out = atlas(biome)
    out.save(Path(root) / OUT_DIR / biome / "atlas.png")
    return out


if __name__ == "__main__":
    for name in sys.argv[1:] or BIOMES:
        build(REPO_ROOT, name)
        print("tiles v2:", name)
