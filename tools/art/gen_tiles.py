"""Biome tilesets: floor, wall block and pit, 64x64 cells, one atlas per biome.

The ground diamond is 64x32 and sits in rows 16..47 of its cell, so the cell's
centre is the tile origin and a wall can rise 16px above it. Atlas columns match
scripts/tiles.gd: FLOOR (0,0), WALL (1,0), PIT (2,0).

    py gen_tiles.py <out_dir> [biome ...]      (no biome = all six)
"""
import sys

import palette
from pixel import Canvas, seeded

CELL = 64
HALF_W = 32
HALF_H = 16
CY = 32  # ground diamond centre row inside the cell
RISE = 16


def in_diamond(x, y, cx, cy, hw, hh):
    return abs(x + 0.5 - cx) / hw + abs(y + 0.5 - cy) / hh <= 1.0


def edge_dist(x, y, cx, cy, hw, hh):
    """0 at the rim, 1 at the centre."""
    return 1.0 - (abs(x + 0.5 - cx) / hw + abs(y + 0.5 - cy) / hh)


def ramps_for(biome):
    """(ground ramp, wall ramp) light -> dark. The mines keep their hand-tuned ramps."""
    if biome == "collapsed_mines":
        return palette.RAMPS["rock"], palette.RAMPS["wall"]
    spec = palette.BIOMES[biome]
    return palette.ramp_from(spec["ground"]), palette.ramp_from(spec["wall"])


def accent(biome, name):
    return palette.hex_rgb(palette.BIOMES[biome][name])


# --- floor ------------------------------------------------------------------

def floor_tile(biome):
    c = Canvas(CELL, CELL)
    rng = seeded("floor" + biome)
    rock, _ = ramps_for(biome)
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
    decorate_floor(c, biome, rng, rock)
    return c


def scatter(c, rng, count, box, fn):
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


def decorate_floor(c, biome, rng, rock):
    box = (12, 22, 52, 42)
    if biome == "collapsed_mines":
        def pebble(x, y):
            c.put(x, y, rock[0]); c.put(x + 1, y, rock[0]); c.put(x, y + 1, rock[3])
        scatter(c, rng, 7, box, pebble)
        for _ in range(2):
            px, py = rng.randint(18, 44), rng.randint(26, 38)
            for step in range(rng.randint(3, 6)):
                if in_diamond(px + step, py + step // 2, HALF_W, CY, HALF_W - 4, HALF_H - 2):
                    c.put(px + step, py + step // 2, rock[3])
    elif biome == "fungal_caverns":
        moss = palette.hex_rgb("#3F7A52")
        glow, violet = accent(biome, "accent2"), accent(biome, "accent1")
        def patch(x, y):
            for dx, dy in ((0, 0), (1, 0), (-1, 0), (0, 1), (2, 1)):
                c.put(x + dx, y + dy, moss)
        scatter(c, rng, 6, box, patch)
        def spore(x, y):
            c.put(x, y, glow)
        scatter(c, rng, 6, box, spore)
        def shroom(x, y):
            c.put(x, y - 1, violet); c.put(x + 1, y - 1, violet); c.put(x, y, rock[3])
        scatter(c, rng, 3, box, shroom)
    elif biome == "crystal_hollows":
        pink, cyan = accent(biome, "accent1"), accent(biome, "accent2")
        def shard(x, y):
            col = pink if rng.random() < 0.5 else cyan
            c.put(x, y - 2, col); c.put(x, y - 1, col); c.put(x, y, col)
            c.put(x - 1, y, palette.mix(col, palette.WHITE, 0.4)); c.put(x + 1, y, palette.mix(col, (0, 0, 0, 255), 0.4))
        scatter(c, rng, 5, box, shard)
        def glint(x, y):
            c.put(x, y, palette.WHITE)
        scatter(c, rng, 4, box, glint)
    elif biome == "drowned_city":
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
        algae, pearl = accent(biome, "accent1"), accent(biome, "accent2")
        def weed(x, y):
            c.put(x, y, algae); c.put(x + 1, y, algae); c.put(x, y - 1, algae)
        scatter(c, rng, 5, box, weed)
        def drop(x, y):
            c.put(x, y, pearl)
        scatter(c, rng, 3, box, drop)
    elif biome == "ember_forge":
        lava, yellow = accent(biome, "accent1"), accent(biome, "accent2")
        # Riveted plates and a jagged lava crack.
        for corner in ((22, 32), (42, 32), (32, 26), (32, 38)):
            c.put(corner[0], corner[1], rock[0])
        px, py = 20, 33
        for step in range(22):
            px += 1
            py += rng.choice((-1, 0, 0, 1))
            if in_diamond(px, py, HALF_W, CY, HALF_W - 3, HALF_H - 2):
                c.put(px, py, lava)
                if step % 4 == 0:
                    c.put(px, py + 1, yellow)
    elif biome == "the_heart":
        vein, bone = accent(biome, "accent1"), accent(biome, "accent2")
        light = accent(biome, "light")
        for _ in range(3):
            px, py = rng.randint(16, 40), rng.randint(26, 38)
            for step in range(rng.randint(5, 9)):
                px += 1
                py += rng.choice((-1, 0, 1))
                if in_diamond(px, py, HALF_W, CY, HALF_W - 4, HALF_H - 2):
                    c.put(px, py, vein)
        def pulse(x, y):
            c.put(x, y, light); c.put(x + 1, y, palette.mix(light, (0, 0, 0, 255), 0.4))
        scatter(c, rng, 3, box, pulse)
        def knob(x, y):
            c.put(x, y, bone)
        scatter(c, rng, 3, box, knob)


# --- wall -------------------------------------------------------------------

def wall_tile(biome):
    c = Canvas(CELL, CELL)
    rng = seeded("wall" + biome)
    _, wall = ramps_for(biome)
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
    decorate_wall(c, biome, rng, wall, top_cy)
    for y in range(top_cy + HALF_H, top_cy + HALF_H + RISE):
        c.put(HALF_W - 1, y, wall[3])
        c.put(HALF_W, y, wall[3])
    c.outline(palette.OUTLINE)
    return c


def left_y(x, top_cy, offset):
    return top_cy + int(x / 2) + offset


def right_y(x, top_cy, offset):
    return top_cy + HALF_H - int((x - HALF_W) / 2) + offset


def decorate_wall(c, biome, rng, wall, top_cy):
    a1, a2 = accent(biome, "accent1"), accent(biome, "accent2")
    if biome == "collapsed_mines":
        timber = palette.RAMPS["timber"]
        for i in range(12):
            c.put(44 + i // 3, top_cy + HALF_H - 8 + i // 2, timber[2])
    elif biome == "fungal_caverns":
        for _ in range(5):
            x = rng.randint(3, 28)
            y = left_y(x, top_cy, rng.randint(3, 12))
            c.put(x, y, a1); c.put(x + 1, y, a1); c.put(x, y + 1, palette.mix(a1, (0, 0, 0, 255), 0.4))
        for _ in range(4):
            x = rng.randint(36, 60)
            c.put(x, right_y(x, top_cy, rng.randint(3, 12)), a2)
    elif biome == "crystal_hollows":
        for _ in range(4):
            x = rng.randint(4, 28)
            y = left_y(x, top_cy, rng.randint(3, 11))
            col = a1 if rng.random() < 0.5 else a2
            c.put(x, y, col); c.put(x, y - 1, col); c.put(x + 1, y, palette.mix(col, palette.WHITE, 0.4))
        for _ in range(3):
            x = rng.randint(38, 60)
            c.put(x, right_y(x, top_cy, rng.randint(3, 11)), a2)
    elif biome == "drowned_city":
        for x in range(2, 30, 6):
            for r in (6, 11):
                c.put(x, left_y(x, top_cy, r), wall[3]); c.put(x + 1, left_y(x + 1, top_cy, r), wall[3])
        for _ in range(6):
            x = rng.randint(2, 28)
            c.put(x, left_y(x, top_cy, rng.randint(10, 14)), a1)
        for _ in range(3):
            x = rng.randint(36, 60)
            c.put(x, right_y(x, top_cy, rng.randint(2, 6)), a2)
    elif biome == "ember_forge":
        for x in range(3, 30, 5):
            c.put(x, left_y(x, top_cy, 3), wall[0]); c.put(x, left_y(x, top_cy, 12), wall[0])
        for _ in range(7):
            x = rng.randint(36, 60)
            y = right_y(x, top_cy, rng.randint(5, 12))
            c.put(x, y, a1)
            if rng.random() < 0.4:
                c.put(x, y + 1, a2)
    elif biome == "the_heart":
        for _ in range(3):
            x = rng.randint(3, 20)
            for step in range(rng.randint(5, 9)):
                c.put(x + step, left_y(x + step, top_cy, 5 + rng.choice((0, 1, 2))), a1)
        for _ in range(4):
            x = rng.randint(38, 60)
            c.put(x, right_y(x, top_cy, rng.randint(2, 12)), accent(biome, "light"))


# --- pit --------------------------------------------------------------------

def pit_tile(biome):
    c = Canvas(CELL, CELL)
    rng = seeded("pit" + biome)
    deep = palette.PIT_DEEP
    mid = palette.PIT_MID
    rim = palette.PIT_RIM
    spec = palette.BIOMES[biome]
    tint = palette.hex_rgb(spec["wall"])
    mid = palette.mix(mid, tint, 0.35)
    rim = palette.mix(rim, tint, 0.55)
    for y in range(CELL):
        for x in range(CELL):
            if not in_diamond(x, y, HALF_W, CY, HALF_W, HALF_H):
                continue
            d = edge_dist(x, y, HALF_W, CY, HALF_W, HALF_H)
            level = d + ((x % 2) + (y % 2) * 2) / 4.0 * 0.12
            c.put(x, y, rim if level < 0.12 else (mid if level < 0.30 else deep))
    glint = palette.hex_rgb(spec["accent2"]) if biome != "collapsed_mines" else palette.RAMPS["copper"][2]
    for _ in range(3):
        x, y = rng.randint(22, 42), rng.randint(28, 36)
        if in_diamond(x, y, HALF_W, CY, HALF_W - 14, HALF_H - 7):
            c.put(x, y, glint)
    return c


def build(out_dir, biome):
    atlas = Canvas(CELL * 3, CELL)
    atlas.blit(floor_tile(biome), 0, 0)
    atlas.blit(wall_tile(biome), CELL, 0)
    atlas.blit(pit_tile(biome), CELL * 2, 0)
    atlas.save("%s/%s/atlas.png" % (out_dir, biome))
    return atlas


if __name__ == "__main__":
    out = sys.argv[1] if len(sys.argv) > 1 else "../../assets/tilesets"
    names = sys.argv[2:] or list(palette.BIOMES)
    for name in names:
        build(out, name)
        print("tiles:", name)
