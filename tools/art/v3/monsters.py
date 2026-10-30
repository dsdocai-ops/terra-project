"""v3 non-humanoid enemies: one front drawing each on a 30x34 canvas (feet on the
bottom rows), turned into the 8-facing idle/walk sheet by `sheet()`."""

from __future__ import annotations

from .core import Canvas, dk, lt, mix
from .hero import FACINGS

red, bone, steel, steelD, gold = "#ff4a4a", "#efe3c4", "#b8c4d0", "#6c7a8c", "#f2c040"


def _c() -> Canvas:
    return Canvas(30, 34)


def _eyes(s, x, y, gap, c=red, big=False):
    s.px(x, y, c); s.px(x + gap, y, c)
    if big:
        s.px(x, y + 1, dk(c, .3)); s.px(x + gap, y + 1, dk(c, .3))


def tick(c):
    s = _c()
    for i in range(3):
        s.line(9 + i * 4, 26, 6 + i * 4, 30, dk(c, .4)); s.line(11 + i * 4, 26, 13 + i * 5, 30, dk(c, .4))
    s.ell(15, 24, 8, 5, c); s.ell(13, 22, 5, 2, lt(c, .3)); s.ell(15, 27, 7, 1, dk(c, .3))
    for x, y in ((10, 20), (14, 19), (18, 20)):
        s.px(x, y, lt(c, .5))
    s.ell(23, 25, 3, 3, dk(c, .2)); _eyes(s, 23, 24, 2)
    return s.outline()


def wisp(c):
    s = _c()
    s.tri(9, 24, 21, 24, 15, 8, c); s.circ(15, 24, 6, c); s.tri(11, 18, 15, 18, 10, 11, lt(c, .3)); s.circ(15, 25, 4, lt(c, .45)); s.circ(15, 26, 2, "#fffbe0")
    for x, y in ((13, 22), (17, 22), (13, 21), (17, 21)):
        s.px(x, y, "#2a1a2e")
    return s.outline()


def bat(c, n=1):
    s = _c()

    def one(x, y):
        s.tri(x - 7, y - 3, x - 1, y - 1, x - 2, y + 3, dk(c, .1)); s.tri(x + 7, y - 3, x + 1, y - 1, x + 2, y + 3, dk(c, .1))
        s.px(x - 6, y - 1, dk(c, .3)); s.px(x + 6, y - 1, dk(c, .3)); s.circ(x, y, 2, c); s.px(x - 1, y - 3, c); s.px(x + 1, y - 3, c)
        s.px(x - 1, y, red); s.px(x + 1, y, red)

    if n == 1:
        one(15, 22)
    else:
        one(9, 16); one(21, 20); one(13, 27)
    return s.outline()


def mush(cap, stem, r=7, cy=18, mouth=False, eye="#2a1a2e", arms=False):
    s = _c()
    s.rect(15 - -(-r // 2), cy, r, 30 - cy, stem); s.rect(15 - -(-r // 2), cy, 1, 30 - cy, lt(stem, .2))
    s.ell(15, cy, r + 3, r - 1, cap); s.rect(15 - r - 3, cy, 2 * r + 7, 2, dk(cap, .3))
    for y in range(cy + 1, 40):
        for x in range(30):
            if s.g(x, y) == cap:
                s.px(x, y, None)
    s.ell(15 - r / 2, cy - r / 2, 2, 1, lt(cap, .5)); s.circ(15 + r / 2, cy - 2, 1, lt(cap, .5)); s.px(15, cy - r + 2, lt(cap, .5))
    _eyes(s, 13, cy + 4, 3, eye, True)
    if mouth:
        s.rect(14, cy + 7, 2, 2, "#2a1a2e")
    if arms:
        s.rect(15 - r - 1, cy + 3, 3, 6, stem); s.rect(15 + r - 1, cy + 3, 3, 6, stem)
    return s.outline()


def moth(c):
    s = _c()
    s.ell(9, 18, 6, 5, c); s.ell(21, 18, 6, 5, c); s.ell(10, 26, 4, 3, dk(c, .15)); s.ell(20, 26, 4, 3, dk(c, .15))
    s.circ(9, 18, 2, lt(c, .6)); s.circ(21, 18, 2, lt(c, .6)); s.ell(15, 22, 2, 6, "#e8dcc0")
    s.line(14, 15, 11, 11, "#e8dcc0"); s.line(16, 15, 19, 11, "#e8dcc0"); s.px(14, 18, "#2a1a2e"); s.px(16, 18, "#2a1a2e")
    return s.outline()


def roots(c):
    s = _c()
    s.ell(15, 29, 10, 2, "#5a3a2a")
    for x0, y0, x1, y1, x2, y2 in ((6, 28, 4, 14, 8, 8), (15, 27, 14, 10, 17, 6), (24, 28, 26, 16, 22, 10)):
        s.line(x0, y0, x1, y1, c, 2); s.line(x1, y1, x2, y2, c, 2); s.px(x2, y2 - 1, lt(c, .3))
    s.circ(15, 23, 3, dk(c, .2)); s.px(14, 23, "#ffe04a"); s.px(16, 23, "#ffe04a")
    return s.outline()


def golem(c, eye="#ffd04a", cracks=None, shards=None):
    s = _c()
    s.rect(9, 25, 5, 5, dk(c, .2)); s.rect(16, 25, 5, 5, dk(c, .2)); s.rect(7, 13, 16, 13, c); s.rect(8, 14, 6, 4, lt(c, .25)); s.rect(18, 21, 4, 4, dk(c, .2))
    s.rect(2, 14, 5, 11, dk(c, .1)); s.rect(23, 14, 5, 11, dk(c, .15)); s.rect(10, 6, 10, 8, c); s.rect(11, 7, 4, 2, lt(c, .3))
    s.rect(12, 10, 2, 1, eye); s.rect(16, 10, 2, 1, eye)
    if cracks:
        s.line(9, 17, 12, 23, cracks); s.line(19, 15, 21, 19, cracks); s.line(14, 8, 13, 12, cracks)
    if shards:
        s.tri(7, 14, 10, 13, 6, 7, shards); s.tri(20, 13, 23, 14, 24, 7, shards); s.tri(13, 7, 17, 7, 15, 3, lt(shards, .3))
    return s.outline()


def turtle(shell):
    s = _c()
    s.rect(6, 27, 3, 3, "#7a8a5a"); s.rect(20, 27, 3, 3, "#7a8a5a"); s.ell(26, 24, 3, 2, "#8a9a6a"); s.px(27, 23, "#2a1a2e")
    s.ell(14, 23, 10, 6, shell); s.rect(4, 24, 21, 4, dk(shell, .25))
    for y in range(29, 34):
        for x in range(30):
            if s.g(x, y) == shell:
                s.px(x, y, None)
    for x, y, g in ((9, 19, "#c87af0"), (14, 17, "#7ad8f0"), (19, 20, "#f07ab0")):
        s.tri(x - 2, y + 3, x + 2, y + 3, x, y - 2, g); s.px(x, y, lt(g, .6))
    return s.outline()


def mimic():
    s, w = _c(), "#a8703a"
    s.rect(5, 16, 20, 14, w); s.rect(5, 16, 20, 2, dk(w, .2)); s.rect(5, 22, 20, 1, gold); s.rect(14, 21, 3, 3, gold); s.rect(6, 18, 18, 4, "#3a1020")
    for x in range(6, 24, 3):
        s.px(x, 18, bone); s.px(x + 1, 21, bone)
    s.rect(11, 20, 8, 2, "#e8607a"); s.rect(5, 12, 20, 4, w); s.rect(5, 12, 20, 1, lt(w, .3)); s.px(9, 14, "#7af0f0"); s.px(20, 14, "#7af0f0")
    s.rect(4, 12, 1, 18, gold); s.rect(25, 12, 1, 18, gold)
    return s.outline()


def eel(c):
    s = _c()
    s.ell(15, 30, 11, 2, "#2a6a8a")
    pts = ((8, 30), (6, 25), (9, 20), (14, 17), (18, 13), (17, 8))
    for (a, b), (d, e) in zip(pts, pts[1:]):
        s.line(a, b, d, e, c, 3)
    s.ell(18, 8, 4, 3, c); s.rect(18, 9, 5, 1, "#2a1a2e"); s.px(17, 6, "#ffe04a"); s.tri(9, 22, 4, 20, 7, 25, lt(c, .3))
    return s.outline()


def crab(c):
    s = _c()
    for i in range(3):
        s.line(9 + i * 2, 25, 4 + i * 2, 30, dk(c, .3)); s.line(21 - i * 2, 25, 26 - i * 2, 30, dk(c, .3))
    s.ell(15, 23, 9, 5, c); s.ell(13, 21, 5, 2, lt(c, .3)); s.circ(4, 16, 3, c); s.circ(26, 16, 3, c); s.rect(3, 13, 2, 2, None); s.rect(25, 13, 2, 2, None)
    s.line(7, 19, 5, 18, c, 2); s.line(23, 19, 25, 18, c, 2)
    for x, y in ((10, 22), (19, 21), (15, 26)):
        s.circ(x, y, 1, "#d8d0c0")
    s.rect(12, 16, 1, 3, dk(c, .3)); s.rect(18, 16, 1, 3, dk(c, .3)); s.px(12, 15, "#2a1a2e"); s.px(18, 15, "#2a1a2e")
    return s.outline()


def imp(c):
    s = _c()
    s.tri(10, 18, 3, 12, 5, 22, "#5a2a2a"); s.tri(20, 18, 27, 12, 25, 22, "#5a2a2a"); s.line(18, 26, 24, 28, c); s.tri(23, 26, 26, 28, 24, 30, c)
    s.rect(11, 18, 8, 8, c); s.rect(11, 26, 3, 4, dk(c, .2)); s.rect(16, 26, 3, 4, dk(c, .2)); s.circ(15, 14, 5, c)
    for x, y in ((11, 9), (10, 8), (19, 9), (20, 8)):
        s.px(x, y, bone)
    s.rect(13, 13, 1, 2, "#ffe04a"); s.rect(17, 13, 1, 2, "#ffe04a"); s.rect(14, 17, 3, 1, "#2a1a2e"); s.circ(15, 22, 2, "#ffb03a")
    return s.outline()


def drone(c):
    s = _c()
    s.rect(9, 6, 12, 2, steelD); s.rect(14, 8, 2, 3, steelD); s.circ(15, 17, 7, c); s.ell(12, 14, 3, 2, lt(c, .3)); s.circ(15, 17, 3, "#3a3a48"); s.circ(15, 17, 1, "#ff8a3a")
    for x in range(8, 23, 3):
        s.px(x, 23, dk(c, .3))
    s.tri(11, 24, 19, 24, 15, 30, "#7a5a3a"); s.rect(13, 28, 4, 2, steelD)
    return s.outline()


def turret():
    s = _c()
    s.rect(7, 26, 16, 4, steelD); s.rect(9, 22, 12, 4, "#8a7a5a"); s.circ(15, 17, 6, "#a88a4a"); s.rect(18, 15, 10, 3, steelD); s.rect(26, 14, 2, 5, "#3a3a48")
    s.circ(14, 17, 2, "#3a3a48"); s.px(14, 17, red); s.ell(13, 13, 3, 1, lt("#a88a4a", .4))
    return s.outline()


def blob(c, veins=None, eye="#ffe04a"):
    s = _c()
    s.ell(15, 24, 10, 6, c); s.ell(15, 29, 11, 1, c); s.ell(11, 21, 4, 2, lt(c, .35))
    if veins:
        s.line(7, 25, 12, 22, veins); s.line(12, 22, 16, 27, veins); s.line(18, 20, 22, 26, veins)
    for a, b, c2, d in ((5, 22, 1, 14), (25, 22, 29, 15), (15, 18, 16, 10)):
        s.line(a, b, c2, d, dk(c, .1), 2)
    _eyes(s, 12, 24, 5, eye, True)
    return s.outline()


ENEMIES = {
    "rock_tick": lambda: tick("#8a7a6a"),
    "lantern_wisp": lambda: wisp("#ff9a3a"),
    "cave_bat_swarm": lambda: bat("#6a4a7a", 3),
    "shroomling": lambda: mush("#d84a5a", "#efe3c4", r=5, cy=21),
    "spore_spitter": lambda: mush("#8a4ab0", "#d8d0b8", r=7, cy=17, mouth=True, eye="#c8ff6a"),
    "mycel_brute": lambda: mush("#b0703a", "#e8dcc0", r=9, cy=14, arms=True, eye=red),
    "glow_moth": lambda: moth("#5ad0d0"),
    "root_strangler": lambda: roots("#7a5a3a"),
    "shard_golem": lambda: golem("#7a8ab0", eye="#ffffff", shards="#9ae0f0"),
    "prism_bat": lambda: bat("#9ad8f0", 1),
    "geode_turtle": lambda: turtle("#8a7a6a"),
    "crystal_mimic": mimic,
    "eel_lurker": lambda: eel("#4a8a6a"),
    "barnacle_crab": lambda: crab("#c8603a"),
    "forge_imp": lambda: imp("#d8402a"),
    "slag_golem": lambda: golem("#4a3a3a", eye="#ffb03a", cracks="#ff8a2a"),
    "bellows_drone": lambda: drone("#b0884a"),
    "clockwork_sentry": turret,
    "veinling": lambda: blob("#8a2a4a", veins="#ff5a7a"),
}

IDLE_BOB = (0, -1)
WALK_BOB = (0, -1, -2, -1, 0, -1)


def facing_frame(base: Canvas, facing: str, frame: int) -> Canvas:
    s = base.copy()
    if facing in ("n", "ne", "nw"):
        s.tint("#24142c", 0.18)
    if facing in ("w", "sw", "nw"):
        s = s.flip_x()
    bob = IDLE_BOB[frame] if frame < 2 else WALK_BOB[frame - 2]
    out = Canvas(s.w, s.h)
    out.blit(s, 0, bob)
    return out


def sheet(base: Canvas, cell: int = 32, scale: int = 2):
    sh = Canvas(cell * 8, cell * 8)
    for row, facing in enumerate(FACINGS):
        for col in range(8):
            f = facing_frame(base, facing, col)
            x0, y0, x1, y1 = base.bbox()
            ox = (cell - (x1 - x0 + 1)) // 2 - x0
            oy = (cell - 2) - y1
            sh.blit(f, col * cell + ox, row * cell + oy)
    return sh.image(scale)
