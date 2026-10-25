"""Shared pixel-art primitives (specs/SPEC-art-audio.md, "Tools").

A Canvas is an indexed-color grid: every cell holds a palette color *name*
(resolved through palette.ALL, or the mapping the Canvas was built with) or
None for transparent. Drawing is hard-edged: no anti-aliasing, no alpha, no
blends. A name the Canvas does not know raises KeyError at draw time, so an
off-palette color fails in the generator, not in review. Export is RGBA with a
transparent background, written deterministically (same canvas, same bytes).

Every color argument below is a palette name from palette.py, never a literal
RGB. Ramps are 4 names light -> dark (palette.MATERIAL, palette.ramp4,
BiomePalette.ground_ramp / wall_ramp).

Direction rule (decision 2026-10-21, Dev A): character, enemy and boss sheets
draw all 8 facings as separate rows. mirror_h() stays for symmetric props, UI
pieces and tiles; it is not a production path for character rows.
"""

from __future__ import annotations

import math
import random
from collections.abc import Callable, Iterable, Mapping, Sequence
from pathlib import Path

from PIL import Image

import palette

Point = tuple[float, float]
Cell = tuple[int, int]
Ramp = Sequence[str]

OUTLINE = "outline"
CLEAR: None = None


class Canvas:
    """Indexed-color grid. Each cell holds a palette color name or None
    (transparent). Exported RGBA with a transparent background, no AA."""

    def __init__(self, width: int, height: int, colors: Mapping[str, str] | None = None) -> None:
        if width <= 0 or height <= 0:
            raise ValueError(f"canvas size must be positive, got {width}x{height}")
        self.w = int(width)
        self.h = int(height)
        self.colors: Mapping[str, str] = colors if colors is not None else palette.ALL
        self.grid: list[list[str | None]] = [[None] * self.w for _ in range(self.h)]

    # --- cells ---------------------------------------------------------------

    def _check(self, color: str | None) -> str | None:
        if color is not None and color not in self.colors:
            raise KeyError(f"{color!r} is not a palette name this canvas knows")
        return color

    def put(self, x: float, y: float, color: str | None) -> None:
        """Sets one cell; off-canvas coordinates are ignored. None clears."""
        xi, yi = int(math.floor(x)), int(math.floor(y))
        if 0 <= xi < self.w and 0 <= yi < self.h:
            self.grid[yi][xi] = self._check(color)

    def get(self, x: float, y: float) -> str | None:
        xi, yi = int(math.floor(x)), int(math.floor(y))
        if 0 <= xi < self.w and 0 <= yi < self.h:
            return self.grid[yi][xi]
        return None

    def opaque(self, x: float, y: float) -> bool:
        return self.get(x, y) is not None

    def cells(self) -> Iterable[tuple[int, int, str]]:
        """Every opaque cell as (x, y, name)."""
        for y, row in enumerate(self.grid):
            for x, name in enumerate(row):
                if name is not None:
                    yield x, y, name

    # --- primitives ----------------------------------------------------------

    def rect(self, x0: float, y0: float, x1: float, y1: float, color: str | None) -> None:
        """Filled box, both corners inclusive."""
        self._check(color)
        for y in range(int(math.floor(min(y0, y1))), int(math.floor(max(y0, y1))) + 1):
            for x in range(int(math.floor(min(x0, x1))), int(math.floor(max(x0, x1))) + 1):
                self.put(x, y, color)

    def line(self, x0: float, y0: float, x1: float, y1: float, color: str | None) -> None:
        """Bresenham line between rounded endpoints."""
        self._check(color)
        xa, ya, xb, yb = int(round(x0)), int(round(y0)), int(round(x1)), int(round(y1))
        dx, dy = abs(xb - xa), -abs(yb - ya)
        sx = 1 if xa < xb else -1
        sy = 1 if ya < yb else -1
        err = dx + dy
        while True:
            self.put(xa, ya, color)
            if xa == xb and ya == yb:
                break
            e2 = 2 * err
            if e2 >= dy:
                err += dy
                xa += sx
            if e2 <= dx:
                err += dx
                ya += sy

    def ellipse(self, cx: float, cy: float, rx: float, ry: float, color: str | None) -> None:
        """Filled ellipse; a cell is inside when its centre is."""
        self._check(color)
        if rx <= 0 or ry <= 0:
            return
        for y in range(int(math.floor(cy - ry)) - 1, int(math.ceil(cy + ry)) + 2):
            for x in range(int(math.floor(cx - rx)) - 1, int(math.ceil(cx + rx)) + 2):
                u = (x + 0.5 - cx) / rx
                v = (y + 0.5 - cy) / ry
                if u * u + v * v <= 1.0:
                    self.put(x, y, color)

    def ellipse_shaded(self, cx: float, cy: float, rx: float, ry: float, ramp: Ramp, light: Point = (-0.6, -0.8)) -> None:
        """Filled ellipse in 4 ramp steps lit from `light` (default top-left):
        the lit cap takes ramp[0], the far rim ramp[3]."""
        if len(ramp) < 4:
            raise ValueError("ellipse_shaded needs a 4-step ramp")
        for name in ramp[:4]:
            self._check(name)
        if rx <= 0 or ry <= 0:
            return
        for y in range(int(math.floor(cy - ry)) - 1, int(math.ceil(cy + ry)) + 2):
            for x in range(int(math.floor(cx - rx)) - 1, int(math.ceil(cx + rx)) + 2):
                u = (x + 0.5 - cx) / rx
                v = (y + 0.5 - cy) / ry
                if u * u + v * v <= 1.0:
                    lit = u * light[0] + v * light[1]  # > 0 faces the light
                    if lit > 0.55:
                        c = ramp[0]
                    elif lit > -0.1:
                        c = ramp[1]
                    elif lit > -0.6:
                        c = ramp[2]
                    else:
                        c = ramp[3]
                    self.put(x, y, c)

    def polygon(self, points: Sequence[Point], color: str | None) -> None:
        """Scanline fill (even-odd) of a convex or simple polygon."""
        self._check(color)
        if len(points) < 3:
            return
        ys = [p[1] for p in points]
        n = len(points)
        for y in range(int(math.floor(min(ys))), int(math.ceil(max(ys))) + 1):
            yc = y + 0.5
            xs: list[float] = []
            for i in range(n):
                (xa, ya), (xb, yb) = points[i], points[(i + 1) % n]
                if ya == yb:
                    continue
                if min(ya, yb) <= yc < max(ya, yb):
                    xs.append(xa + (yc - ya) * (xb - xa) / (yb - ya))
            xs.sort()
            for i in range(0, len(xs) - 1, 2):
                for x in range(int(math.floor(xs[i] + 0.5)), int(math.floor(xs[i + 1] + 0.5))):
                    self.put(x, y, color)

    def blit(self, other: Canvas, ox: int, oy: int) -> None:
        """Copies other's opaque cells onto this canvas at (ox, oy)."""
        for x, y, name in other.cells():
            self.put(ox + x, oy + y, name)

    # --- passes --------------------------------------------------------------

    def outline(self, color: str = OUTLINE) -> None:
        """1 px outline: every transparent cell 4-adjacent to an opaque one
        takes `color` (near-black #1A1420 by default)."""
        self._check(color)
        marks: list[Cell] = []
        for y in range(self.h):
            for x in range(self.w):
                if self.grid[y][x] is not None:
                    continue
                for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                    if self.opaque(x + dx, y + dy):
                        marks.append((x, y))
                        break
        for x, y in marks:
            self.grid[y][x] = color

    def copy(self) -> Canvas:
        out = Canvas(self.w, self.h, self.colors)
        out.grid = [row[:] for row in self.grid]
        return out

    # --- export --------------------------------------------------------------

    def to_image(self) -> Image.Image:
        img = Image.new("RGBA", (self.w, self.h), (0, 0, 0, 0))
        px = img.load()
        for x, y, name in self.cells():
            r, g, b = palette.rgb(self.colors[name])
            px[x, y] = (r, g, b, 255)
        return img

    def save(self, path: Path | str) -> None:
        save_png(self, Path(path))

    def rgb_set(self) -> frozenset[tuple[int, int, int]]:
        """Distinct RGB values this canvas uses (for palette checks)."""
        return frozenset(palette.rgb(self.colors[name]) for _, _, name in self.cells())


# --- module functions (the spec's API) ------------------------------------------

def outline(canvas: Canvas, color: str = OUTLINE) -> Canvas:
    """1 px outline around every opaque region (near-black #1A1420 by default).
    Returns a new canvas."""
    out = canvas.copy()
    out.outline(color)
    return out


def shade(canvas: Canvas, ramp: Ramp, light_dir: tuple[int, int] = (-1, -1)) -> Canvas:
    """Relights every cell painted in ramp[1] (the base step): cells whose
    neighbour toward the light is transparent become ramp[0] (highlight), cells
    whose neighbour away from the light is transparent become ramp[2] (shadow),
    and cells open on both sides (1 px lines) stay base. ramp[3] is left for
    the caller's inner lines. Light from top-left by default: top faces highlight, right and
    bottom faces shadow. Returns a new canvas."""
    if len(ramp) < 3:
        raise ValueError("shade needs at least 3 ramp steps")
    out = canvas.copy()
    base = ramp[1]
    lx, ly = light_dir
    for x, y, name in canvas.cells():
        if name != base:
            continue
        toward = not canvas.opaque(x + lx, y + ly)
        away = not canvas.opaque(x - lx, y - ly)
        if toward and not away:
            out.put(x, y, ramp[0])
        elif away and not toward:
            out.put(x, y, ramp[2])
    return out


def dither(canvas: Canvas, a: str, b: str, region: tuple[int, int, int, int]) -> Canvas:
    """Checker dither between two palette colors over region (x0, y0, x1, y1),
    corners inclusive, only where the canvas is already opaque. Tiles and
    bosses only (SPEC-art-audio, shading rules). Returns a new canvas."""
    out = canvas.copy()
    x0, y0, x1, y1 = region
    for y in range(min(y0, y1), max(y0, y1) + 1):
        for x in range(min(x0, x1), max(x0, x1) + 1):
            if canvas.opaque(x, y):
                out.put(x, y, a if (x + y) % 2 == 0 else b)
    return out


def iso_diamond(width: int = 64, height: int = 32) -> list[Cell]:
    """Cells of a 2:1 isometric floor diamond (Diamond Down) in a width x
    height box, origin top-left of the box."""
    hw, hh = width / 2.0, height / 2.0
    out: list[Cell] = []
    for y in range(height):
        for x in range(width):
            if abs(x + 0.5 - hw) / hw + abs(y + 0.5 - hh) / hh <= 1.0:
                out.append((x, y))
    return out


def iso_box(width: int = 64, height: int = 64, top: int = 32) -> dict[str, list[Cell]]:
    """Cells of an iso wall block by face. The top face is a `width` x `top`
    diamond at the top of the box; the left and right faces hang from its
    lower edges down to the bottom row."""
    hw = width / 2.0
    hh = top / 2.0
    faces: dict[str, list[Cell]] = {"top": [], "left": [], "right": []}
    for y in range(height):
        for x in range(width):
            px, py = x + 0.5, y + 0.5
            if abs(px - hw) / hw + abs(py - hh) / hh <= 1.0:
                faces["top"].append((x, y))
                continue
            # Lower edge of the diamond under this column.
            edge = hh + hh * (1.0 - abs(px - hw) / hw)
            if py > edge and y < height:
                faces["left" if px < hw else "right"].append((x, y))
    return faces


def mirror_h(canvas: Canvas) -> Canvas:
    """Horizontal mirror. For symmetric props, UI and tiles only: character
    rows are drawn for all 8 facings (decision 2026-10-21)."""
    out = Canvas(canvas.w, canvas.h, canvas.colors)
    out.grid = [row[::-1] for row in canvas.grid]
    return out


def sheet(rows: Sequence[Sequence[Canvas]]) -> Canvas:
    """Packs frames into a sprite sheet: rows are directions (8, in
    Facing.SUFFIXES order), columns are frames. Every frame must share one
    size; short rows are padded with transparent cells."""
    if not rows or not rows[0]:
        raise ValueError("sheet needs at least one frame")
    fw, fh = rows[0][0].w, rows[0][0].h
    colors = rows[0][0].colors
    columns = max(len(r) for r in rows)
    out = Canvas(fw * columns, fh * len(rows), colors)
    for ry, row in enumerate(rows):
        for cx, frame in enumerate(row):
            if (frame.w, frame.h) != (fw, fh):
                raise ValueError(f"frame {ry},{cx} is {frame.w}x{frame.h}, expected {fw}x{fh}")
            out.blit(frame, cx * fw, ry * fh)
    return out


def save_png(canvas: Canvas, path: Path) -> None:
    """Writes RGBA PNG deterministically (same canvas, same bytes): no
    metadata, fixed compression."""
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    canvas.to_image().save(path, format="PNG", optimize=False, compress_level=9)


def seeded(name: str) -> random.Random:
    """A reproducible RNG per asset so re-running a generator is byte-identical."""
    return random.Random(sum(ord(c) * (i + 1) for i, c in enumerate(name)))


# --- v2 primitives (art direction v2, decisions 2026-10-24) ---------------------
#
# Ports of the approved mockup kit (docs/art-direction/v2/mockup-src/). World art
# is drawn at quarter resolution, so the iso helpers below work on a 16x8 floor
# diamond and generators ship the result through export_scaled(canvas, 4). UI
# pieces are drawn on the 320x180 grid and exported 3x. Every color argument is
# a palette name, as above.

FaceColor = str | Callable[[int, int], str]


def _i32(v: int) -> int:
    v &= 0xFFFFFFFF
    return v - 0x100000000 if v & 0x80000000 else v


def _imul(a: int, b: int) -> int:
    return _i32((a & 0xFFFFFFFF) * (b & 0xFFFFFFFF))


def hash01(a: float, b: float) -> float:
    """Deterministic hash of two numbers to [0, 1). Bit-for-bit the mockup's
    `hs(a, b)`, so a recipe ported from mockup-src scatters the same way."""
    ia, ib = _i32(int(a)), _i32(int(b))
    n = _i32(_imul(ia, 374761393) + _imul(ib, 668265263))
    n = _imul(n ^ ((n & 0xFFFFFFFF) >> 13), 1274126177)
    return ((n ^ ((n & 0xFFFFFFFF) >> 16)) & 0xFFFFFFFF) / 4294967296


def _round(v: float) -> int:
    """JavaScript Math.round (halves go up), which the mockups used."""
    return int(math.floor(v + 0.5))


def _face(color: FaceColor, px: int, r: int) -> str:
    return color(px, r) if callable(color) else color


def circle(canvas: Canvas, cx: int, cy: int, r: int, color: str) -> None:
    """Filled pixel circle as the mockups draw it: one span per row, half
    width round(sqrt(r^2 - dy^2))."""
    canvas._check(color)
    for dy in range(-r, r + 1):
        w = _round(math.sqrt(max(0, r * r - dy * dy)))
        for x in range(cx - w, cx + w + 1):
            canvas.put(x, cy + dy, color)


def tri(canvas: Canvas, a: Point, b: Point, c: Point, color: str) -> None:
    canvas.polygon([a, b, c], color)


def quad(canvas: Canvas, a: Point, b: Point, c: Point, d: Point, color: str) -> None:
    canvas.polygon([a, b, c, d], color)


def lerp(a: Point, b: Point, t: float) -> Point:
    return (a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t)


def iso_tile(canvas: Canvas, x: int, y: int, color: str, hi: str | None = None, lo: str | None = None) -> None:
    """Quarter-resolution floor diamond, 16x8, with (x, y) its top vertex.
    Optional 2 px bevels: `hi` on the top-left edge, `lo` on the bottom-right."""
    canvas._check(color)
    for r in range(8):
        k = r if r < 4 else 7 - r
        w = 2 * k + 2
        for px in range(x - w, x + w):
            canvas.put(px, y + r, color)
    if hi:
        for r in range(4):
            canvas.put(x - 2 * r - 2, y + r, hi)
            canvas.put(x - 2 * r - 1, y + r, hi)
    if lo:
        for r in range(4, 8):
            canvas.put(x + 2 * (7 - r), y + r, lo)
            canvas.put(x + 2 * (7 - r) + 1, y + r, lo)


def iso_block(canvas: Canvas, x: int, y: int, h: int, top: str, left: FaceColor, right: FaceColor, top_hi: str | None = None) -> None:
    """Quarter-resolution block standing on the floor diamond whose top vertex
    is (x, y): two h-tall faces and a raised top diamond. `left` and `right`
    are a palette name or a texture function (screen_x, r) -> name, where r
    counts rows up from the face's bottom edge (stone_face, plank_face)."""
    for u in range(8):
        lx, lt = x - 8 + u, y - h + 5 + (u >> 1)
        rx, rt = x + u, y - h + 8 - (u >> 1)
        for r in range(h):
            canvas.put(lx, lt + h - 1 - r, _face(left, lx, r))
            canvas.put(rx, rt + h - 1 - r, _face(right, rx, r))
    iso_tile(canvas, x, y - h, top, top_hi)


def stone_face(ramp: Mapping[str, str], seed: int) -> Callable[[int, int], str]:
    """Coursed-stone texture for iso_block faces (the mockup's stonePx).
    Courses are 4 rows high with mortar along the bottom row; stones are 6 px
    long, offset per course. ramp keys: a, b, c (stone tones), hi (top row of a
    course), lo (row above the mortar), m (mortar), and optional ore (rare
    flecks)."""
    for key in ("a", "b", "c", "hi", "lo", "m"):
        if key not in ramp:
            raise KeyError(f"stone_face ramp needs {key!r}")

    def color(px: int, r: int) -> str:
        band = r // 4
        sx = px + int(hash01(band, seed) * 6) + 600
        ri = r & 3
        if ri == 0 or sx % 6 == 0:
            return ramp["m"]
        v = hash01(sx // 6, band + seed * 7)
        if v > 0.97 and "ore" in ramp:
            return ramp["ore"]
        if ri == 3:
            return ramp["hi"]
        if ri == 1:
            return ramp["lo"]
        return ramp["a"] if v < 0.4 else ramp["b"] if v < 0.8 else ramp["c"]

    return color


def plank_face(base: str, line: str, h: int, period: int = 3, foundation: Callable[[int, int], str] | None = None, foundation_rows: int = 4) -> Callable[[int, int], str]:
    """Horizontal boards for an h-tall face: a `line` row every `period` rows
    counted from the top, and an optional `foundation` texture under the
    bottom `foundation_rows` rows (the mockup houses' stone base)."""

    def color(px: int, r: int) -> str:
        if foundation is not None and r < foundation_rows:
            return foundation(px, r)
        return line if (h - r) % period == 0 else base

    return color


def brick_base(stone: str, stone_alt: str, mortar: str) -> Callable[[int, int], str]:
    """The 4-row stone foundation under plank walls: 4 px bricks, staggered
    every 2 rows, mortar on row 2 and every 4th column."""

    def color(px: int, r: int) -> str:
        shift = 2 if r > 2 else 0
        if r == 2 or ((px + shift) & 3) == 0:
            return mortar
        return stone if ((px + shift) >> 2) & 1 else stone_alt

    return color


def shingle_roof(canvas: Canvas, eave_l: Point, eave_r: Point, ridge_r: Point, ridge_l: Point, base: str, stripe: str) -> None:
    """One roof plane from the eave (eave_l -> eave_r) up to the ridge
    (ridge_l -> ridge_r): filled in `base`, with shingle courses parallel to
    the eave and staggered tab marks every 4 px."""
    quad(canvas, eave_l, eave_r, ridge_r, ridge_l, base)
    rise = abs(eave_l[1] - ridge_l[1])
    n = max(3, _round(rise / 2.2))
    for k in range(1, n):
        t = k / n
        p, q = lerp(eave_l, ridge_l, t), lerp(eave_r, ridge_r, t)
        canvas.line(p[0], p[1], q[0], q[1], stripe)
        length = q[0] - p[0]
        u = (k % 2) * 2
        while u < length:
            canvas.put(p[0] + u, p[1] + u / 2 - 1, stripe)
            u += 4


def _skewed_columns(origin: Point, slope: int, fx: float, span: float, width: int) -> list[tuple[int, int]]:
    """Columns of a feature placed a fraction fx along a sloped face edge:
    (screen_x, bottom_y) for each of `width` columns."""
    ox = _round(origin[0])
    cx0 = _round(origin[0] + fx * span)
    return [(cx0 + u, int(math.floor(origin[1] + (cx0 + u - ox) * slope / 2))) for u in range(width)]


def iso_window(canvas: Canvas, origin: Point, slope: int, fx: float, span: float, r0: int, pal: Mapping[str, str]) -> None:
    """7x8 framed window with a cross bar, sill and shutters on a sloped face.
    pal keys: frame, cross, glass, glass_hi, sill, shutter."""
    cols = _skewed_columns(origin, slope, fx, span, 9)
    for u, (cx, by) in enumerate(cols[1:8]):
        for r in range(r0, r0 + 8):
            if u in (0, 6) or r in (r0, r0 + 7):
                c = pal["frame"]
            elif u == 3 or r == r0 + 4:
                c = pal["cross"]
            elif u < 3 and r > r0 + 4:
                c = pal["glass_hi"]
            else:
                c = pal["glass"]
            canvas.put(cx, by - r, c)
        canvas.put(cx, by - r0 + 1, pal["sill"])
    for cx, by in (cols[0], cols[8]):
        for r in range(r0 + 1, r0 + 7):
            canvas.put(cx, by - r, pal["shutter"])


def iso_door(canvas: Canvas, origin: Point, slope: int, fx: float, span: float, pal: Mapping[str, str]) -> None:
    """7x12 plank door on a sloped face, with a step and a knob.
    pal keys: door_a, door_b, door_frame, step, knob."""
    cols = _skewed_columns(origin, slope, fx, span, 7)
    for u, (cx, by) in enumerate(cols):
        for r in range(12):
            c = pal["door_frame"] if u in (0, 6) or r == 11 else (pal["door_a"] if u & 1 else pal["door_b"])
            canvas.put(cx, by - r, c)
        canvas.put(cx, by + 1, pal["step"])
    cx, by = cols[5]
    canvas.put(cx, by - 6, pal["knob"])


HOUSE_KEYS: tuple[str, ...] = (
    "wall_l", "wall_l_line", "wall_r", "wall_r_line",
    "base_stone", "base_stone_alt", "base_mortar", "base_stone_r", "base_stone_alt_r", "base_mortar_r",
    "edge_dark", "edge_light",
    "roof", "roof_stripe", "roof_hi", "roof_edge", "roof_back", "roof_outline",
    "frame", "cross", "glass", "glass_hi", "sill", "shutter",
    "door_a", "door_b", "door_frame", "step", "knob",
    "chimney", "chimney_side", "chimney_cap",
)


def iso_house(
    canvas: Canvas, x: int, y: int, w: int, d: int, h: int, rh: int, pal: Mapping[str, str],
    windows_left: Sequence[float] = (), windows_right: Sequence[float] = (),
    door_left: float | None = None, door_right: float | None = None, chimney: float | None = None,
) -> None:
    """Plank-and-shingle building (the mockup's house2) on a w x d tile
    footprint whose top vertex is (x, y): plank walls on a brick foundation,
    windows and doors placed by fraction along each wall, a shingled gable
    roof with its ridge along the w axis, a gable window, and an optional
    chimney at fraction `chimney` along the ridge. pal must hold every name in
    HOUSE_KEYS."""
    missing = [k for k in HOUSE_KEYS if k not in pal]
    if missing:
        raise KeyError(f"iso_house palette missing {missing}")
    top = (x, y)
    right = (x + 8 * w, y + 4 * w)
    bottom = (x + 8 * w - 8 * d, y + 4 * w + 4 * d)
    left = (x - 8 * d, y + 4 * d)

    def wall(origin: Point, end: Point, slope: int, fill: Callable[[int, int], str]) -> None:
        x0, x1 = _round(origin[0]), _round(end[0])
        for cx in range(x0, x1):
            by = int(math.floor(origin[1] + (cx - x0) * slope / 2))
            for r in range(h):
                canvas.put(cx, by - r, fill(cx, r))

    wall(left, bottom, 1, plank_face(pal["wall_l"], pal["wall_l_line"], h, foundation=brick_base(pal["base_stone"], pal["base_stone_alt"], pal["base_mortar"])))
    wall(bottom, right, -1, plank_face(pal["wall_r"], pal["wall_r_line"], h, foundation=brick_base(pal["base_stone_r"], pal["base_stone_alt_r"], pal["base_mortar_r"])))
    for r in range(h):
        canvas.put(left[0], left[1] - r, pal["edge_dark"])
        canvas.put(bottom[0], bottom[1] - r, pal["edge_light"])
        canvas.put(right[0] - 1, right[1] - r, pal["edge_dark"])
    for f in windows_left:
        iso_window(canvas, left, 1, f, bottom[0] - left[0], 6, pal)
    for f in windows_right:
        iso_window(canvas, bottom, -1, f, right[0] - bottom[0], 6, pal)
    if door_left is not None:
        iso_door(canvas, left, 1, door_left, bottom[0] - left[0], pal)
    if door_right is not None:
        iso_door(canvas, bottom, -1, door_right, right[0] - bottom[0], pal)

    def up(p: Point, dh: float) -> Point:
        return (p[0], p[1] - dh)

    def off(p: Point, dx: float, dy: float) -> Point:
        return (p[0] + dx, p[1] + dy)

    lh, bh, th, rh_ = up(left, h), up(bottom, h), up(top, h), up(right, h)
    ridge_l = up(lerp(top, left, 0.5), h + rh)
    ridge_r = up(lerp(right, bottom, 0.5), h + rh)
    quad(canvas, off(th, -1, -1), off(rh_, 2, 0), off(ridge_r, 2, 0), off(ridge_l, -1, 0), pal["roof_back"])
    tri(canvas, bh, rh_, ridge_r, pal["wall_r"])
    for k in range(3, rh, 3):
        p, q = lerp(bh, ridge_r, k / rh), lerp(rh_, ridge_r, k / rh)
        canvas.line(p[0], p[1], q[0], q[1], pal["wall_r_line"])
    gw = lerp(lerp(bh, rh_, 0.5), ridge_r, 0.4)
    circle(canvas, _round(gw[0]), _round(gw[1]), 2, pal["frame"])
    canvas.rect(gw[0] - 1, gw[1] - 1, gw[0], gw[1], pal["glass"])
    a, b, c, e = off(lh, -2, 2), off(bh, 1, 3), off(ridge_r, 2, 0), off(ridge_l, -2, 0)
    shingle_roof(canvas, a, b, c, e, pal["roof"], pal["roof_stripe"])
    canvas.line(a[0], a[1], b[0], b[1], pal["roof_edge"])
    canvas.line(a[0], a[1] + 1, b[0], b[1] + 1, pal["roof_outline"])
    canvas.line(e[0], e[1], c[0], c[1], pal["roof_hi"])
    canvas.line(e[0], e[1] - 1, c[0], c[1] - 1, pal["roof_edge"])
    canvas.line(b[0], b[1], c[0], c[1], pal["roof_edge"])
    canvas.line(b[0] + 1, b[1], c[0] + 1, c[1], pal["roof_stripe"])
    if chimney is not None:
        cp = lerp(e, c, chimney)
        canvas.rect(cp[0] - 2, cp[1] - 9, cp[0] + 2, cp[1] - 1, pal["chimney"])
        canvas.rect(cp[0] + 1, cp[1] - 9, cp[0] + 2, cp[1] - 1, pal["chimney_side"])
        canvas.rect(cp[0] - 3, cp[1] - 10, cp[0] + 3, cp[1] - 9, pal["chimney_cap"])


def scatter(canvas: Canvas, count: int, fn: Callable[[Canvas, int, int, float, int], None], seed: int, mask: Callable[[int, int], bool] | None = None) -> None:
    """Deterministic detail scatter (pebbles, grass tufts, cracks): `count`
    hashed points over the canvas; fn(canvas, x, y, t, n) runs for each point
    the mask accepts, with t in [0, 1) choosing the detail."""
    for n in range(count):
        x = int(hash01(n, seed + 11) * canvas.w)
        y = int(hash01(n, seed + 13) * canvas.h)
        if mask is None or mask(x, y):
            fn(canvas, x, y, hash01(n, seed + 17), n)


def sprite_from_rows(rows: Sequence[str], mapping: Mapping[str, str], colors: Mapping[str, str] | None = None) -> Canvas:
    """Canvas from string rows, one character per pixel: '.' is transparent,
    every other character is looked up in `mapping` (char -> palette name).
    The mockup sprites (BODY, GOB, BAT2, icons) are written this way."""
    if not rows:
        raise ValueError("sprite needs at least one row")
    width = len(rows[0])
    for i, row in enumerate(rows):
        if len(row) != width:
            raise ValueError(f"row {i} is {len(row)} wide, expected {width}")
    out = Canvas(width, len(rows), colors)
    for y, row in enumerate(rows):
        for x, ch in enumerate(row):
            if ch == ".":
                continue
            if ch not in mapping:
                raise KeyError(f"row {y} uses {ch!r}, which the mapping does not define")
            out.put(x, y, mapping[ch])
    return out


def _oct(canvas: Canvas, x: int, y: int, w: int, h: int, cut: int, color: str) -> None:
    for r in range(h):
        k = cut - r if r < cut else (r - (h - 1 - cut) if r > h - 1 - cut else 0)
        for px in range(x + k, x + w - k):
            canvas.put(px, y + r, color)


def oct_socket(size: int, rim: Sequence[str], fill: str, shade: str, outline_color: str = OUTLINE, colors: Mapping[str, str] | None = None) -> Canvas:
    """Octagonal ability/relic socket (the mockup's sock): outline, a bevelled
    rim (rim = (mid, hi, lo)), an inner outline, the `fill` well and a 1 px
    `shade` line under the top edge."""
    if size < 12:
        raise ValueError("oct_socket needs size >= 12")
    mid, hi, lo = rim
    c = Canvas(size, size, colors)
    _oct(c, 0, 0, size, size, 3, outline_color)
    _oct(c, 1, 1, size - 2, size - 2, 2, lo)
    _oct(c, 1, 1, size - 3, size - 3, 2, hi)
    _oct(c, 2, 2, size - 4, size - 4, 2, mid)
    _oct(c, 3, 3, size - 6, size - 6, 2, outline_color)
    _oct(c, 4, 4, size - 8, size - 8, 1, fill)
    c.rect(5, 4, size - 6, 4, shade)
    return c


def export_scaled(canvas: Canvas, k: int) -> Canvas:
    """Nearest-neighbour k-times upscale (4 for world art, 3 for UI). Returns a
    Canvas, so the palette check and save_png work unchanged."""
    if k < 1:
        raise ValueError("scale must be >= 1")
    out = Canvas(canvas.w * k, canvas.h * k, canvas.colors)
    for y, row in enumerate(canvas.grid):
        wide = [name for name in row for _ in range(k)]
        for j in range(k):
            out.grid[y * k + j] = wide[:]
    return out
