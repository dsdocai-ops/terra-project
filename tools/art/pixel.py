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
from collections.abc import Iterable, Mapping, Sequence
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
