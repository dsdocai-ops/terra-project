"""v3 world art: biome tile atlases, town ground and pit edge, town buildings in their
four states, and dungeon and town props. Drawn at native size, shipped 2x."""

from __future__ import annotations

import math

from .core import Canvas, dk, lt, mix, ramp, rng

gold = "#f2c040"

# Atlas cells (scripts/tiles.gd): FLOOR (0,0), WALL (1,0), PIT (2,0), floor variants on row 1.
BIOMES = {
    "collapsed_mines": {"floor": "#6e5c4a", "wall": "#4a3a30", "top": "#8a7662", "speck": "#d8803a", "seed": 1},
    "fungal_caverns": {"floor": "#3e4a52", "wall": "#30283c", "top": "#4a5a4a", "speck": "#6aa06a", "moss": "#4a6a4a", "seed": 2},
    "crystal_hollows": {"floor": "#4a4a66", "wall": "#33334e", "top": "#5a5a7a", "speck": "#7ad8f0", "seed": 3},
    "drowned_city": {"floor": "#5a7470", "wall": "#3a5050", "top": "#6a8a84", "speck": "#9ae0f0", "seed": 4},
    "ember_forge": {"floor": "#4a3c3a", "wall": "#2e2424", "top": "#5a4a46", "speck": "#ff7a2a", "grate": True, "seed": 5},
    "the_heart": {"floor": "#6a2e3e", "wall": "#4a1a2a", "top": "#8a3a4a", "speck": "#ff4a6a", "veins": True, "seed": 6},
}


def _diamond(s: Canvas, cx: float, ty: int, colfn) -> None:
    for j in range(16):
        w = (j + 1) * 4 if j < 8 else (16 - j) * 4
        for i in range(w):
            colour = colfn(i, j, w)
            if colour:
                s.px(cx - w / 2 + i, ty + j, colour)


def _floor_fn(b: dict, variant: int):
    r = rng(b["seed"] * 101 + variant * 7)
    base = b["floor"]

    def f(i, j, w):
        n = r()
        c = base
        if b.get("moss") and n < 0.25:
            c = b["moss"]
        elif b.get("grate") and (i % 6 == 0 or j % 4 == 0):
            c = dk(base, .25)
        elif b.get("veins") and (i + j * 2) % 11 == 0:
            c = "#c83a5a"
        elif n < 0.12:
            c = dk(base, .12)
        elif n > 0.93:
            c = lt(base, .1)
        if variant == 1 and n > 0.965:
            c = b["speck"]
        if variant == 2 and (i - w / 2) ** 2 / 9 + (j - 8) ** 2 / 4 < 1:
            c = dk(base, .3)
        if variant == 3 and n > 0.9:
            c = lt(base, .2)
        if j == 0 or i == 0:
            c = lt(c, .12)
        return c

    return f


def _wall(s: Canvas, cx: int, ty: int, rise: int, b: dict) -> None:
    side = b["wall"]
    for d in range(rise, -1, -1):
        y = ty - d
        for j in range(16):
            w = (j + 1) * 4 if j < 8 else (16 - j) * 4
            for i in range(w):
                x = cx - w / 2 + i
                c = side if x < cx else dk(side, .25)
                if d % 6 == 3 and j in (7, 8):
                    c = dk(side, .35)
                s.px(x, y + j, c)
    r = rng(b["seed"] * 13)
    _diamond(s, cx, ty - rise, lambda i, j, w: lt(b["top"], .12) if (j == 0 or i == 0) else (dk(b["top"], .1) if r() < .1 else b["top"]))


def _pit(s: Canvas, cx: int, ty: int, b: dict) -> None:
    depth = ("#140a14", "#1e1020", "#2a1a2e")
    _diamond(s, cx, ty, lambda i, j, w: dk(b["floor"], .45) if (j <= 1 or i <= 1 or i >= w - 2) else depth[min(2, abs(j - 8) // 3)])


def biome_atlas(biome: str, cell_h: int) -> Canvas:
    b = BIOMES[biome]
    s = Canvas(96, cell_h * 2)
    ty, rise = cell_h // 2 - 8, cell_h // 2 - 8
    _diamond(s, 16, ty, _floor_fn(b, 0))
    _wall(s, 48, ty, rise, b)
    _pit(s, 80, ty, b)
    for k in range(3):
        _diamond(s, 16 + 32 * k, cell_h + ty, _floor_fn(b, k + 1))
    return s


def town_atlas() -> Canvas:
    s = Canvas(96, 32)
    r = rng(77)
    _diamond(s, 16, 8, lambda i, j, w: "#6a9a3a" if r() < .1 else ("#a8d060" if r() > .97 else "#82b44a"))
    b = {"wall": "#8a6040", "top": "#c8a070", "seed": 9}
    _diamond(s, 48, 8, lambda i, j, w: "#82b44a")
    for x in (40, 47, 54):
        s.rect(x, 4, 2, 10, "#c8a070"); s.px(x, 4, "#e8c898")
    s.rect(38, 6, 20, 2, "#b08858"); s.rect(38, 10, 20, 2, dk("#b08858", .15))
    _pit(s, 80, 8, {"floor": "#82b44a"})
    return s


def pit_edge(stage: int) -> Canvas:
    s = Canvas(128, 64)
    rx = (60, 52, 44, 36)[stage]
    ry = rx / 2
    cx, cy = 64, 32
    s.ell(cx, cy, rx, ry, "#6a5a3a"); s.ell(cx, cy, rx - 3, ry - 2, "#4a3a2a"); s.ell(cx, cy + 1, rx - 6, ry - 4, "#2a1a24")
    s.ell(cx, cy + 2, rx * .78, ry * .7, "#1a0e1a"); s.ell(cx, cy + 3, rx * .55, ry * .48, "#120814"); s.ell(cx, cy + 4, rx * .28, ry * .24, "#2a1040"); s.ell(cx, cy + 4, rx * .12, ry * .1, "#5a2a8a")
    r = rng(stage + 40)
    for _ in range(28):
        a = r() * math.pi * 2
        s.circ(cx + math.cos(a) * rx * .97, cy + math.sin(a) * ry * .95, 1 + int(r() * 2), "#8a7a5a" if r() < .5 else "#5a4a3a")
    return s


# ---- props ---------------------------------------------------------------------------------
def crate() -> Canvas:
    s, w = Canvas(16, 16), "#a8703a"
    s.rect(1, 4, 14, 11, w); s.rect(1, 4, 14, 1, lt(w, .3)); s.line(1, 4, 14, 14, dk(w, .3)); s.line(14, 4, 1, 14, dk(w, .3))
    s.rect(4, 1, 8, 3, w); s.rect(4, 1, 8, 1, lt(w, .3))
    return s.outline()


def lamp() -> Canvas:
    s = Canvas(8, 20)
    s.rect(3, 6, 2, 13, "#5a3820"); s.rect(2, 18, 4, 2, "#3a2414"); s.rect(1, 1, 6, 6, "#3a3448"); s.rect(2, 2, 4, 4, "#ffd27a"); s.px(2, 2, "#fff4c8")
    return s.outline()


def well() -> Canvas:
    s = Canvas(16, 20)
    s.rect(2, 10, 12, 8, "#8a8478")
    for x in (2, 6, 10):
        s.rect(x, 10, 1, 8, "#5a564e")
    s.ell(8, 10, 5, 2, "#2a1a2e"); s.rect(2, 3, 2, 8, "#7a5232"); s.rect(12, 3, 2, 8, "#7a5232"); s.tri(0, 4, 15, 4, 8, 0, "#a8423a")
    return s.outline()


def chest() -> Canvas:
    s, w = Canvas(16, 14), "#a8703a"
    s.rect(1, 5, 14, 8, w); s.rect(1, 2, 14, 4, lt(w, .1)); s.rect(1, 6, 14, 1, gold); s.rect(7, 5, 2, 3, gold); s.px(7, 6, "#3a2414")
    s.rect(1, 2, 1, 11, gold); s.rect(14, 2, 1, 11, gold)
    return s.outline()


def mining_node() -> Canvas:
    s = Canvas(16, 14)
    s.ell(8, 8, 7, 5, "#7a6e62"); s.ell(6, 6, 3, 2, lt("#7a6e62", .25))
    for x, y in ((4, 7), (9, 5), (11, 9), (6, 10)):
        s.px(x, y, "#d8803a"); s.px(x + 1, y, "#f8b070")
    return s.outline()


def breakable() -> Canvas:
    s, w = Canvas(12, 14), "#9a6438"
    s.ell(6, 7, 5, 6, w); s.rect(1, 3, 10, 1, "#5a5a6a"); s.rect(1, 10, 10, 1, "#5a5a6a"); s.rect(3, 2, 1, 10, lt(w, .2))
    return s.outline()


def lore_page() -> Canvas:
    s = Canvas(12, 10)
    s.rect(1, 1, 10, 8, "#f4e0b0"); s.rect(0, 1, 1, 8, "#c8a068"); s.rect(11, 1, 1, 8, "#c8a068")
    for y in (3, 5, 7):
        s.rect(3, y, 6, 1, "#8a6a4a")
    s.px(9, 2, "#c83a3a")
    return s.outline()


def rope() -> Canvas:
    s = Canvas(14, 22)
    s.rect(2, 19, 10, 2, "#5a3820"); s.rect(6, 0, 2, 20, "#c8a070")
    for y in range(0, 20, 3):
        s.px(6, y, "#8a6a40"); s.px(7, y + 1, "#8a6a40")
    s.ell(7, 18, 5, 2, "#b08858"); s.ell(7, 18, 3, 1, "#8a6a40")
    return s.outline()


def shrine() -> Canvas:
    s, st = Canvas(16, 22), "#9a94a8"
    s.rect(2, 16, 12, 5, st); s.rect(4, 6, 8, 11, st); s.tri(3, 7, 12, 7, 8, 1, dk(st, .1)); s.rect(5, 8, 6, 6, "#3a2a5a")
    s.circ(8, 11, 2, "#c8a0ff"); s.px(7, 10, "#ffffff"); s.rect(2, 16, 12, 1, lt(st, .2))
    return s.outline()


# ---- town buildings ------------------------------------------------------------------------
ICON = {
    "anvil": [".........", ".#######.", "##+#####.", "..####...", "..####...", ".######..", "........."],
    "flask": ["...##....", "...##....", "..#++#...", ".#++++#..", ".#++++#..", "..####...", "........."],
    "map": ["#.###.##.", "##.###.#.", "#.#+#.##.", "##.###.#.", "#.###.##.", ".........", "........."],
    "eye": [".........", "..#####..", ".#.+++.#.", "#.+.#.+.#", ".#.+++.#.", "..#####..", "........."],
    "mug": [".#####...", ".#+++####", ".#+++#..#", ".#+++####", ".#+++#...", ".#####...", "........."],
    "gem": ["..#####..", ".#+#+#+#.", "..#+#+#..", "...#+#...", "....#....", ".........", "........."],
    "book": [".#######.", ".#+++#+#.", ".#+++#+#.", ".#+++#+#.", ".#######.", ".........", "........."],
    "hat": ["...###...", "..#####..", "..#+++#..", "#########", ".........", ".........", "........."],
    "sword": ["......##.", ".....##..", "....##...", ".#.##....", "..##.....", ".#.#.....", "#........"],
    "tent": ["....#....", "...###...", "..##+##..", ".##+++##.", "##+++++##", ".........", "........."],
    "scroll": [".#######.", "#+++++++#", ".#+###+#.", ".#+++++#.", ".#+###+#.", "#+++++++#", ".#######."],
}
BUILD = {
    "blacksmith": {"w": 34, "h": 22, "rh": 12, "wall": "#8a8478", "stone": True, "roof": "#5a4a5a", "trim": "#4a3a2a", "chimney": True, "sign": "anvil"},
    "alchemist": {"w": 30, "h": 22, "rh": 13, "wall": "#d8c8a0", "timber": True, "roof": "#4a8a5a", "trim": "#5a3a2a", "chimney": True, "sign": "flask", "signC": "#3a8a3a"},
    "map_room": {"w": 28, "h": 20, "rh": 8, "wall": "#c8b890", "timber": True, "shape": "tower", "roof": "#3a5a9a", "trim": "#5a3a2a", "sign": "map"},
    "shrine_of_echoes": {"w": 30, "h": 22, "rh": 14, "wall": "#9a94a8", "stone": True, "shape": "temple", "roof": "#5a4a8a", "trim": "#3a3048", "glow": "#c8a0ff", "door": "#3a2a5a", "sign": "eye"},
    "tavern": {"w": 40, "h": 24, "rh": 14, "wall": "#e0d0a8", "timber": True, "roof": "#a8423a", "trim": "#5a3a22", "chimney": True, "sign": "mug", "signC": "#a8703a"},
    "relic_vault": {"w": 32, "h": 22, "rh": 10, "wall": "#7a7468", "stone": True, "roof": "#4a4a5a", "trim": "#c8a040", "door": "#a08040", "sign": "gem", "signC": "#3a8ab0"},
    "rune_library": {"w": 32, "h": 24, "rh": 12, "wall": "#c8c0b0", "stone": True, "roof": "#3a4a8a", "trim": "#3a3048", "sign": "book", "signC": "#3a4a8a", "banner": "#3a6ac8"},
    "training_grounds": {"shape": "yard", "sign": "sword"},
    "rescue_camp": {"shape": "tent", "sign": "tent"},
    "bounty_board": {"shape": "board", "sign": "scroll"},
    "wardrobe": {"w": 28, "h": 22, "rh": 11, "wall": "#e8c8c8", "timber": True, "roof": "#8a4a8a", "trim": "#5a3a4a", "sign": "hat", "signC": "#8a4a8a", "banner": "#8a4a8a"},
}


def _fence() -> Canvas:
    s, w = Canvas(30, 12), "#c8a070"
    for x in (1, 10, 19, 27):
        s.rect(x, 1, 2, 10, w)
    s.rect(0, 3, 30, 2, w); s.rect(0, 7, 30, 2, dk(w, .15))
    return s.outline()


def _dummy() -> Canvas:
    s = Canvas(14, 26)
    s.rect(6, 12, 2, 13, "#7a5232"); s.rect(2, 12, 10, 2, "#7a5232"); s.ell(7, 15, 4, 5, "#d8b878"); s.circ(7, 6, 4, "#d8b878")
    s.line(5, 13, 9, 17, "#a07848"); s.px(6, 5, "#3a2a1a"); s.px(8, 5, "#3a2a1a")
    return s.outline()


def _sign_patch(kind: str) -> Canvas:
    k = BUILD[kind]
    s = Canvas(56, 56)
    s.ell(28, 50, 22, 5, "#9a7a50"); s.ell(28, 50, 19, 4, "#b8946a")
    for x, y in ((14, 49), (40, 51), (22, 52)):
        s.circ(x, y, 1, "#7a6e62")
    s.rect(27, 34, 2, 16, "#5a3820")
    s.rect(20, 26, 16, 11, "#c8a070"); s.rect(20, 26, 16, 1, lt("#c8a070", .3))
    s.rows(23, 28, ICON[k["sign"]], {"#": k.get("signC", "#3a2a1a"), "+": lt(k.get("signC", "#3a2a1a"), .5)})
    s.rect(30, 46, 6, 4, "#a8703a"); s.rect(31, 44, 4, 2, "#c8a070")
    return s.outline()


def building(kind: str, lvl: int) -> Canvas:
    """lvl 0 sign patch, 1 ruined, 2 rebuilt, 3 upgraded."""
    if lvl == 0:
        return _sign_patch(kind)
    k = BUILD[kind]
    s = Canvas(56, 56)
    shape = k.get("shape", "house")
    if shape == "yard":
        s.blit(_fence(), 2, 40); s.blit(_fence(), 26, 40); s.blit(_dummy(), 10, 22)
        if lvl > 1:
            s.blit(_dummy(), 30, 22)
        if lvl > 2:
            s.rect(22, 14, 2, 30, "#7a5232"); s.rect(24, 14, 10, 7, "#c8402a")
        s.rect(0, 51, 56, 4, "#7a9a4a")
        return s.outline()
    if shape == "board":
        s.rect(10, 22, 2, 30, "#7a5232"); s.rect(44, 22, 2, 30, "#7a5232"); s.rect(8, 18, 40, 22, "#a8703a")
        s.tri(6, 18, 50, 18, 28, 8, "#7a6a5a" if lvl == 1 else "#a8423a")
        n = (2, 4, 6)[lvl - 1]
        for i in range(n):
            px, py = 11 + (i % 3) * 12, 21 + (i // 3) * 9
            s.rect(px, py, 9, 7, "#f0e4c8"); s.rect(px + 1, py + 2, 7, 1, "#8a7a6a"); s.rect(px + 1, py + 4, 5, 1, "#8a7a6a"); s.px(px + 4, py, "#c83a3a")
        if lvl == 3:
            s.circ(28, 9, 2, gold)
        return s.outline()
    if shape == "tent":
        cols = ("#c8a070", "#a8703a", "#8a9a6a")
        for i in range(lvl):
            tx = 6 + i * 16
            s.tri(tx, 50, tx + 20, 50, tx + 10, 32, cols[i]); s.tri(tx + 7, 50, tx + 13, 50, tx + 10, 40, dk(cols[i], .4))
        if lvl > 1:
            s.blit(lamp(), 44, 30)
        s.ell(28, 52, 4, 2, "#ff8a3a")
        return s.outline()
    W = k["w"] + (4 if lvl == 3 else 0)
    x0, wall_top = (56 - W) // 2, 56 - 4 - k["h"]
    wall = mix(k["wall"], "#7a7068", .35) if lvl == 1 else k["wall"]
    s.rect(x0, wall_top, W, k["h"], wall)
    if k.get("stone"):
        for y in range(wall_top + 2, 52, 4):
            for x in range(x0 + (0 if (y // 4) % 2 else 3), x0 + W, 6):
                s.rect(x, y, 1, 3, dk(wall, .2))
            s.rect(x0, y + 3, W, 1, dk(wall, .12))
    if k.get("timber"):
        s.rect(x0, wall_top, W, 2, k["trim"])
        for x in (x0, x0 + W - 3, x0 + W // 2 - 1):
            s.rect(x, wall_top, 3, k["h"], k["trim"])
        s.line(x0 + 3, wall_top + 2, x0 + W / 2 - 2, 51, k["trim"])
    s.rect(x0 - 1, 52, W + 2, 3, dk(wall, .35))
    door = k.get("door", "#6a4024")
    dx = x0 + W // 2 - 4
    s.rect(dx, 39, 8, 13, door); s.rect(dx, 39, 8, 1, lt(door, .3)); s.px(dx + 6, 46, gold); s.rect(dx - 1, 38, 10, 1, k["trim"])

    def win(wx, wy):
        s.rect(wx, wy, 7, 7, k["trim"])
        if lvl == 1:
            s.rect(wx + 1, wy + 1, 5, 5, "#3a2a2a"); s.line(wx, wy + 1, wx + 6, wy + 5, "#a8703a"); s.line(wx, wy + 5, wx + 6, wy + 1, "#a8703a")
        else:
            s.rect(wx + 1, wy + 1, 5, 5, "#ffd27a"); s.rect(wx + 1, wy + 1, 2, 2, "#fff0c0"); s.rect(wx + 3, wy + 1, 1, 5, k["trim"]); s.rect(wx + 1, wy + 3, 5, 1, k["trim"])
        if lvl == 3:
            s.rect(wx - 1, wy + 7, 9, 2, "#7a5232"); s.px(wx + 1, wy + 6, "#e8506a"); s.px(wx + 4, wy + 6, "#f2d04a"); s.px(wx + 6, wy + 6, "#e8506a")

    win(x0 + 4, wall_top + 6); win(x0 + W - 11, wall_top + 6)
    rc = mix(k["roof"], "#6a6058", .45) if lvl == 1 else k["roof"]
    r_top = wall_top - k["rh"]
    if shape == "temple":
        s.tri(x0 - 4, wall_top, x0 + W + 3, wall_top, x0 + W / 2, r_top, rc); s.rect(x0 - 4, wall_top, W + 8, 2, dk(rc, .3))
        for x in (x0 + 2, x0 + W - 5):
            s.rect(x, wall_top + 2, 3, k["h"] - 2, lt(wall, .25))
        s.circ(x0 + W / 2, wall_top - k["rh"] / 2 + 2, 3, k["glow"])
    elif shape == "tower":
        s.rect(x0 + W / 2 - 8, r_top - 12, 16, 16, wall); s.tri(x0 + W / 2 - 11, r_top - 12, x0 + W / 2 + 10, r_top - 12, x0 + W / 2, r_top - 24, rc)
        win(int(x0 + W / 2 - 4), r_top - 8); s.tri(x0 - 3, wall_top + 1, x0 + W + 2, wall_top + 1, x0 + W / 2, r_top + 2, rc); s.rect(x0 + W / 2 + 6, r_top - 18, 6, 3, "#c8a040")
    else:
        for y in range(r_top, wall_top + 2):
            t = (y - r_top) / (wall_top + 1 - r_top)
            half = round(6 + t * (W / 2 + 4 - 6))
            s.rect(x0 + W / 2 - half, y, half * 2, 1, dk(rc, .18) if (y - r_top) % 3 == 0 else rc)
        s.rect(x0 + W / 2 - 6, r_top, 12, 1, lt(rc, .3))
    if lvl == 1 and shape != "temple":
        s.rect(x0 + 8, wall_top - 6, 4, 2, "#2a1a1a"); s.rect(x0 + W - 14, wall_top - 4, 5, 2, "#b08a5a"); s.rect(x0 + 2, wall_top + k["h"] - 10, 6, 1, "#a8703a")
    if k.get("chimney"):
        s.rect(x0 + W - 12, r_top - 2, 5, 9, "#7a6e62"); s.rect(x0 + W - 13, r_top - 3, 7, 2, "#8a8478")
        if lvl > 1:
            s.circ(x0 + W - 9, r_top - 7, 2, "#d8d0c8"); s.circ(x0 + W - 7, r_top - 11, 3, "#e8e0d8")
    sx, sy = x0 + W - 9, wall_top + 16
    s.rect(sx - 1, sy - 2, 1, 3, "#5a3820"); s.rect(sx - 2, sy, 11, 9, "#8a6a4a" if lvl == 1 else "#c8a070")
    s.rows(sx - 1, sy + 1, ICON[k["sign"]], {"#": k.get("signC", "#3a2a1a"), "+": lt(k.get("signC", "#3a2a1a"), .5)})
    if lvl == 3:
        s.rect(x0 - 4, wall_top + 2, 2, 22, "#7a5232"); s.rect(x0 - 2, wall_top + 2, 6, 8, k.get("banner", "#c8402a")); s.px(x0, wall_top + 5, gold)
        s.blit(lamp(), x0 + W + 1, 32)
    return s.outline()


STATES = ("sign", "ruined", "rebuilt", "upgraded")
