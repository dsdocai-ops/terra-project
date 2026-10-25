"""v2 character and enemy sheets (art direction v2, D1/D2).

Sheets keep the v1 layout so tools/make_sprite_frames.gd reads them unchanged:
one row per facing in Facing.SUFFIXES order (s, sw, w, nw, n, ne, e, se),
columns 0..1 idle, 2..7 walk. Frames are drawn at quarter resolution and
shipped 4x: humanoids 16x24 drawn (64x96 shipped, feet on row 92), small
enemies 16x16 drawn (64x64 shipped, feet on row 60).

Every facing is its own drawing (decision 2026-10-21): front, back and side
views are separate row sets, and the west-facing rows are not mirrors of the
east ones (asymmetric details such as Wren's braid or a side-swapped eye are
placed per facing). Small enemies derive their facings from one front drawing
by moving or hiding face pixels; that is a first pass for Dev A's review.

Recipes and colors are the approved mockups' (docs/art-direction/v2/mockup-src/
lib2.js: BODY, GOB, BAT2) on palette.V2 names.

    py tools/art/gen_sprites_v2.py
"""

from __future__ import annotations

from collections.abc import Callable, Sequence
from pathlib import Path

import palette
import pixel
from pixel import Canvas, sheet

REPO_ROOT = Path(__file__).resolve().parents[2]
PLAYER_DIR = Path("assets/sprites/players")
ENEMY_DIR = Path("assets/sprites/enemies")
SCALE = 4
IDLE_FRAMES = 2
WALK_FRAMES = 6
SUFFIXES: tuple[str, ...] = ("s", "sw", "w", "nw", "n", "ne", "e", "se")

Rows = list[str]

# --- the BODY template, one row set per view ------------------------------------
# Characters: o outline, Y/y helmet, L lamp, H hair, S/s skin, e eye, J/j jacket,
# B strap, G glove, N/n pants, K boot (palette.CHARACTER_CHARS order).

FRONT: Rows = [
    ".....oooo.....", "....oYYYYo....", "...oYYLLYYo...", "..oyYYYYYYyo..", "..oyyyyyyyyo..",
    "..oHHSSSSHHo..", "..oHSeSSeSHo..", "..oHsSSSSsHo..", "..oHoSSSSoHo..", "...ooJSSJoHo..",
    "..oJJJBJJJJoH.", ".oJjJJBJJJJjo.", ".oJjJJBJJJJjo.", ".oGoJJJJJJoGo.", "..ooBBBBBBoo..",
]
FRONT_RIGHT: Rows = [
    ".....oooo.....", "....oYYYYo....", "...oYYYLLYo...", "..oyYYYYYYyo..", "..oyyyyyyyyo..",
    "..oHHSSSSSHo..", "..oHSSeSSeSo..", "..oHsSSSSSso..", "..oHHoSSSSo...", "...ooJSSJoHo..",
    "..oJJJBJJJJoH.", ".oJjJJBJJJJjo.", ".oJjJJBJJJJjo.", ".oGoJJJJJJoGo.", "..ooBBBBBBoo..",
]
BACK: Rows = [
    ".....oooo.....", "....oYYYYo....", "...oYYYYYYo...", "..oyYYYYYYyo..", "..oyyyyyyyyo..",
    "..oHHHHHHHHo..", "..oHHHHHHHHo..", "..oHHHHHHHHo..", "..oHHHHHHHHo..", "...ooHHHHHoo..",
    ".HoJJBJJBJJo..", ".oJjJBJJBJJjo.", ".oJjJJBBJJJjo.", ".oGoJJJJJJoGo.", "..ooBBBBBBoo..",
]
BACK_RIGHT: Rows = [
    ".....oooo.....", "....oYYYYo....", "...oYYYYYLo...", "..oyYYYYYYyo..", "..oyyyyyyyyo..",
    "..oHHHHHHHHo..", "..oHHHHHHHHo..", "..oHHHHHHHso..", "..oHHHHHHHso..", "...ooHHHHHoo..",
    ".HoJJBJJBJJo..", ".oJjJBJJBJJjo.", ".oJjJJBBJJJjo.", ".oGoJJJJJJoGo.", "..ooBBBBBBoo..",
]
SIDE_RIGHT: Rows = [
    ".....oooo.....", "....oYYYYoo...", "...oYYYYYLLo..", "..oyYYYYYYYo..", "..oyyyyyyyyyo.",
    "..oHHHSSSSo...", "..oHHSSSeSo...", "..oHHSSSSSSo..", "..oHHoSSSSo...", "...oHoJSSo....",
    "...oHJJJJJo...", "...oJJjBJJJo..", "...oJJjBJJJo..", "...oJJSGJJo...", "....oBBBBBo...",
]

LEGS_FRONT = {
    "stand": ["...oNNNNNNo...", "...oNNnnNNo...", "...oNNooNNo...", "...oNo..oNo...", "..oKKo..oKKo..", "..oooo..oooo.."],
    "a":     ["...oNNNNNNo...", "...oNNnnNNo...", "..oNNo.oNNo...", "..oNo...oNo...", ".oKKo...oKKo..", ".oooo...oooo.."],
    "b":     ["...oNNNNNNo...", "...oNNnnNNo...", "...oNNo.oNNo..", "...oNo...oNo..", "..oKKo...oKKo.", "..oooo...oooo."],
}
LEGS_SIDE = {
    "stand": ["....oNNNNo....", "....oNNnNo....", "....oNNoNo....", "....oNooNo....", "...oKKooKKo...", "...oooooooo..."],
    "a":     ["....oNNNNo....", "...oNNonNo....", "...oNo.oNo....", "..oNo...oNo...", ".oKKo...oKKo..", ".oooo...oooo.."],
    "b":     ["....oNNNNo....", "....oNnoNNo...", "....oNo.oNo...", "...oNo...oNo..", "..oKKo...oKKo.", "..oooo...oooo."],
}
WALK_CYCLE = ("stand", "a", "a", "stand", "b", "b")


def _mirror(rows: Rows) -> Rows:
    return [r[::-1] for r in rows]


def _swap(rows: Rows, edits: Sequence[tuple[int, int, str]]) -> Rows:
    out = [list(r) for r in rows]
    for x, y, ch in edits:
        out[y][x] = ch
    return ["".join(r) for r in out]


def _no_braid(rows: Rows) -> Rows:
    """The braid hangs on Wren's left shoulder. A view from her right side
    hides it: hair pixels below the head line become jacket or clear."""
    out = []
    for y, row in enumerate(rows):
        if y >= 9:
            row = row.replace("H", "J") if y > 9 else row.replace("Ho", "Jo")
            row = row.replace("JJoJ.", "JJo..").replace("oJ.", "o..")
        out.append(row)
    return out


def body_views() -> dict[str, tuple[Rows, dict[str, Rows]]]:
    """Upper body rows and leg set per facing suffix."""
    side_left = _no_braid(_mirror(SIDE_RIGHT))
    front_left = _no_braid(_mirror(FRONT_RIGHT))
    back_left = _swap(_mirror(BACK_RIGHT), [(12, 10, "."), (1, 10, "H"), (2, 10, "o")])
    legs_side_left = {k: _mirror(v) for k, v in LEGS_SIDE.items()}
    return {
        "s": (FRONT, LEGS_FRONT),
        "se": (FRONT_RIGHT, LEGS_FRONT),
        "e": (SIDE_RIGHT, LEGS_SIDE),
        "ne": (BACK_RIGHT, LEGS_FRONT),
        "n": (BACK, LEGS_FRONT),
        "nw": (back_left, LEGS_FRONT),
        "w": (side_left, legs_side_left),
        "sw": (front_left, LEGS_FRONT),
    }


def _frame(rows: Rows, mapping: dict[str, str], colors: dict[str, str], w: int, h: int, bob: bool) -> Canvas:
    """Places a sprite feet-down, centered, in a w x h drawn frame. A bob frame
    drops the upper body one row by removing the row under the belt."""
    if bob and len(rows) > 16:
        rows = ["." * len(rows[0])] + rows[:15] + rows[16:]
    sprite = pixel.sprite_from_rows(rows, mapping, colors)
    out = Canvas(w, h, colors)
    out.blit(sprite, (w - sprite.w) // 2, h - sprite.h)
    return out


def body_sheet(who: str) -> Canvas:
    colors = dict(palette.ALL)
    mapping = palette.character(who)
    views = body_views()
    rows_out: list[list[Canvas]] = []
    for suffix in SUFFIXES:
        upper, legs = views[suffix]
        row: list[Canvas] = []
        for i in range(IDLE_FRAMES):
            row.append(_frame(upper + legs["stand"], mapping, colors, 16, 24, bob=(i == 1)))
        for i, pose in enumerate(WALK_CYCLE):
            row.append(_frame(upper + legs[pose], mapping, colors, 16, 24, bob=pose != "stand"))
        rows_out.append(row)
    return pixel.export_scaled(sheet(rows_out), SCALE)


# --- small and non-BODY enemies ------------------------------------------------

class Critter:
    """A one-drawing enemy: front rows, its mapping, which characters are face
    pixels (moved per facing) and which body character they sit on."""

    def __init__(self, rows: Rows, mapping: dict[str, str], face: str, skin: str, w: int, h: int,
                 walk: Callable[[Rows, int], Rows] | None = None) -> None:
        self.rows, self.mapping, self.face, self.skin, self.w, self.h = rows, mapping, face, skin, w, h
        self.walk = walk

    def view(self, suffix: str) -> Rows:
        """Back views hide the face; side views slide it toward the facing."""
        if suffix in ("n", "ne", "nw"):
            rows = ["".join(self.skin if ch in self.face else ch for ch in r) for r in self.rows]
            # A sliver of face shows on the near cheek in the 3/4 back views.
            return rows if suffix == "n" else self._shift(self.rows, 1 if suffix == "ne" else -1, keep_only_edge=True)
        dx = {"s": 0, "se": 1, "e": 2, "sw": -1, "w": -2}[suffix]
        return self._shift(self.rows, dx)

    def _shift(self, rows: Rows, dx: int, keep_only_edge: bool = False) -> Rows:
        grid = [list(r) for r in rows]
        faces = [(x, y, ch) for y, r in enumerate(rows) for x, ch in enumerate(r) if ch in self.face]
        if not faces:
            return list(rows)  # faceless (the wisp's flame): every facing reads the same
        for x, y, _ in faces:
            grid[y][x] = self.skin
        if keep_only_edge:
            faces = [max(faces, key=lambda f: f[0])] if dx > 0 else [min(faces, key=lambda f: f[0])]
        for x, y, ch in faces:
            nx = x + dx
            if 0 <= nx < len(grid[y]) and grid[y][nx] == self.skin:
                grid[y][nx] = ch
        return ["".join(r) for r in grid]


def _flap(rows: Rows, i: int) -> Rows:
    """Bat wing beat: on odd frames the wing tips (outer columns) lift a row."""
    if i % 2 == 0:
        return rows
    w = len(rows[0])
    out = [list(r) for r in rows]
    for x in (0, 1, w - 2, w - 1):
        col = [rows[y][x] for y in range(len(rows))]
        col = col[1:] + ["."]
        for y in range(len(rows)):
            out[y][x] = col[y]
    return ["".join(r) for r in out]


def _flicker(rows: Rows, i: int) -> Rows:
    """Wisp flame: the core and its rim trade places every other frame."""
    if i % 2 == 0:
        return rows
    return [r.replace("W", "#").replace("Y", "W").replace("#", "Y") for r in rows]


GOBLIN = Critter(
    ["..o......o..", ".oGo....oGo.", ".oGGooooGGo.", "..oGGGGGGo..", ".oGGeGGeGGo.", ".oGGGGGGGGo.", "..oGmmmmGo..",
     "...oooooo...", "..oLLLLLLo.f", ".oGLLlLLLGor", ".oGoLLLLoGor", "..ooLLLLoo.r", "...oDooDo...", "..oKKooKKo..",
     "..oooooooo.."],
    {"o": "rubble_2", "G": "party_lime_2", "e": "rage_0", "m": "timber_7", "L": "timber_2", "l": "timber_0", "D": "timber_6",
     "K": "rubble_2", "r": "danger_0", "f": "glow_2"},
    face="em", skin="G", w=16, h=24,
)
BAT = Critter(
    ["o...........o", "oo..o...o..oo", "oBo.oBoBo.oBo", "oBBooBBBooBBo", "oBBBBEBEBBBBo", ".oBBBBBBBBBo.", "..oBo.o.oBo..",
     "...o.....o..."],
    {"o": "void_7", "B": "echo_6", "E": "danger_0"},
    face="E", skin="B", w=16, h=16, walk=_flap,
)
ROCK_TICK = Critter(
    ["....oooo....", "..ooRRRRoo..", ".oRRrRRRrRo.", ".oRRRRRRRRo.", "oeRRRRRRRReo", ".oRRRRRRRRo.", "o.oLoLLoLo.o",
     "...o.oo.o..."],
    {"o": "rubble_2", "R": "mine_stone_3", "r": "mine_stone_0", "e": "danger_0", "L": "mine_stone_7"},
    face="e", skin="R", w=16, h=16,
)
LANTERN_WISP = Critter(
    ["....oo....", "...oYYo...", "..oYWWYo..", "..oYWWYo..", ".oYYWWYYo.", ".oOYYYYOo.", "..oOOOOo..", "...oOOo...",
     "....oo....", "...o..o...", "..o....o..", ".........."],
    {"o": "lamp_5", "Y": "glow_2", "W": "glow_0", "O": "lamp_2"},
    face="", skin="Y", w=16, h=16, walk=_flicker,
)
CRITTERS: dict[str, Critter] = {
    "dynamite_goblin": GOBLIN,
    "cave_bat_swarm": BAT,
    "rock_tick": ROCK_TICK,
    "lantern_wisp": LANTERN_WISP,
}


def critter_sheet(c: Critter) -> Canvas:
    colors = dict(palette.ALL)
    rows_out: list[list[Canvas]] = []
    for suffix in SUFFIXES:
        base = c.view(suffix)
        row: list[Canvas] = []
        for i in range(IDLE_FRAMES):
            row.append(_frame(base, c.mapping, colors, c.w, c.h, bob=False) if i == 0 else _lifted(base, c, colors))
        for i in range(WALK_FRAMES):
            rows = c.walk(base, i) if c.walk else base
            row.append(_frame(rows, c.mapping, colors, c.w, c.h, bob=False) if i % 3 else _lifted(rows, c, colors))
        rows_out.append(row)
    return pixel.export_scaled(sheet(rows_out), SCALE)


def _lifted(rows: Rows, c: Critter, colors: dict[str, str]) -> Canvas:
    """A one-row hop: the sprite drawn one row higher."""
    frame = _frame(rows, c.mapping, colors, c.w, c.h, bob=False)
    out = Canvas(c.w, c.h, colors)
    out.blit(frame, 0, -1)
    return out


# --- registry ----------------------------------------------------------------------

PLAYERS: tuple[str, ...] = ("wren", "kestrel", "ivy", "brann")
# v1 sheets these replace (gen_enemies.py skips them).
V2_ENEMIES: tuple[str, ...] = ("hollow_miner", *CRITTERS)


def enemy_sheet(enemy_id: str) -> Canvas:
    if enemy_id == "hollow_miner":
        return body_sheet("hollow_miner")
    return critter_sheet(CRITTERS[enemy_id])


def build(root: Path) -> None:
    for who in PLAYERS:
        body_sheet(who).save(Path(root) / PLAYER_DIR / f"{who}.png")
    for enemy_id in V2_ENEMIES:
        enemy_sheet(enemy_id).save(Path(root) / ENEMY_DIR / f"{enemy_id}_sheet.png")


def allowed_rgb() -> frozenset[tuple[int, int, int]]:
    """Every color the v2 sheets may use: the mines v2 set, the UI set (critter
    glows and outlines) and every character palette."""
    names: dict[str, str] = {**palette.v2_colors("collapsed_mines"), **palette.v2_colors("ui")}
    for who in palette.V2_CHARACTERS:
        names.update({f"char_{who}_{s}": v for s, v in zip(palette.CHARACTER_SLOTS, palette.V2_CHARACTERS[who], strict=True)})
    return frozenset(palette.rgb_set(names.values()))


if __name__ == "__main__":
    build(REPO_ROOT)
    print("sprites v2:", ", ".join((*PLAYERS, *V2_ENEMIES)))
