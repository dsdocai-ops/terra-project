"""Art direction v3 pixel engine: hex-colour canvas, primitives, hue-shifted ramps,
silhouette shading and selective outlines.

v3 replaces the palette-name rule with derived ramps: every material is one base
colour and `ramp()` derives its outline, shadow, light and shine tones (shadows lean
violet, highlights lean warm). Deterministic: no randomness except `rng(seed)`.
"""

from __future__ import annotations

import colorsys
import math
from functools import lru_cache
from pathlib import Path

from PIL import Image


def hex_rgb(c: str) -> tuple[int, int, int]:
    c = c.lstrip("#")
    return int(c[0:2], 16), int(c[2:4], 16), int(c[4:6], 16)


def rgb_hex(r: float, g: float, b: float) -> str:
    return "#" + "".join(f"{max(0, min(255, round(v))):02x}" for v in (r, g, b))


def mix(a: str, b: str, t: float) -> str:
    A, B = hex_rgb(a), hex_rgb(b)
    return rgb_hex(*(A[i] + (B[i] - A[i]) * t for i in range(3)))


def dk(c: str, t: float = 0.3) -> str:
    return mix(c, "#24142c", t)


def lt(c: str, t: float = 0.3) -> str:
    return mix(c, "#fff4d6", t)


def _hsl(c: str) -> tuple[float, float, float]:
    r, g, b = (v / 255 for v in hex_rgb(c))
    h, l, s = colorsys.rgb_to_hls(r, g, b)
    return h * 360, s, l


def _from_hsl(h: float, s: float, l: float) -> str:
    r, g, b = colorsys.hls_to_rgb((h % 360) / 360, max(0, min(1, l)), max(0, min(1, s)))
    return rgb_hex(r * 255, g * 255, b * 255)


def _toward(a: float, t: float, amt: float) -> float:
    d = ((t - a + 540) % 360) - 180
    return a + math.copysign(min(abs(d), amt), d)


@lru_cache(maxsize=None)
def ramp(base: str, shift: float = 14) -> tuple[str, str, str, str, str]:
    """(outline, shadow, base, light, shine) for one material."""
    h, s, l = _hsl(base)
    return (
        _from_hsl(_toward(h, 262, shift * 2.2), min(1, s * 0.9 + 0.12), max(0.07, l * 0.38)),
        _from_hsl(_toward(h, 262, shift), min(1, s + 0.08), l * 0.74),
        base,
        _from_hsl(_toward(h, 52, shift * 0.8), s * 0.95, l + (1 - l) * 0.28),
        _from_hsl(_toward(h, 52, shift * 1.4), s * 0.8, l + (1 - l) * 0.55),
    )


def rng(seed: int):
    s = (seed & 0xFFFFFFFF) or 1

    def nxt() -> float:
        nonlocal s
        s ^= (s << 13) & 0xFFFFFFFF
        s ^= s >> 17
        s ^= (s << 5) & 0xFFFFFFFF
        return s / 4294967296

    return nxt


def _lum(c: str) -> float:
    r, g, b = hex_rgb(c)
    return r * 0.3 + g * 0.59 + b * 0.11


class Canvas:
    def __init__(self, w: int, h: int) -> None:
        self.w, self.h = w, h
        self.p: list[str | None] = [None] * (w * h)

    def px(self, x: float, y: float, c: str | None) -> None:
        x, y = int(math.floor(x + 0.5)), int(math.floor(y + 0.5))
        if 0 <= x < self.w and 0 <= y < self.h:
            self.p[y * self.w + x] = c

    def g(self, x: int, y: int) -> str | None:
        if 0 <= x < self.w and 0 <= y < self.h:
            return self.p[y * self.w + x]
        return None

    def rect(self, x: float, y: float, w: int, h: int, c: str | None) -> "Canvas":
        for j in range(int(h)):
            for i in range(int(w)):
                self.px(x + i, y + j, c)
        return self

    def ell(self, cx: float, cy: float, rx: float, ry: float, c: str | None) -> "Canvas":
        for y in range(math.floor(cy - ry - 1), math.ceil(cy + ry + 2)):
            for x in range(math.floor(cx - rx - 1), math.ceil(cx + rx + 2)):
                dx, dy = (x - cx) / (rx + 0.5), (y - cy) / (ry + 0.5)
                if dx * dx + dy * dy <= 1:
                    self.px(x, y, c)
        return self

    def circ(self, cx: float, cy: float, r: float, c: str | None) -> "Canvas":
        return self.ell(cx, cy, r, r, c)

    def ring(self, cx: float, cy: float, r: float, c: str, t: float = 1) -> "Canvas":
        for y in range(math.floor(cy - r - 1), math.ceil(cy + r + 2)):
            for x in range(math.floor(cx - r - 1), math.ceil(cx + r + 2)):
                d = math.hypot(x - cx, y - cy)
                if r + 0.5 - t < d <= r + 0.5:
                    self.px(x, y, c)
        return self

    def line(self, x0: float, y0: float, x1: float, y1: float, c: str, w: int = 1) -> "Canvas":
        n = max(abs(x1 - x0), abs(y1 - y0), 1)
        steps = int(math.ceil(n))
        for i in range(steps + 1):
            x, y = x0 + (x1 - x0) * i / steps, y0 + (y1 - y0) * i / steps
            if w == 1:
                self.px(x, y, c)
            else:
                self.rect(round(x - (w - 1) / 2), round(y - (w - 1) / 2), w, w, c)
        return self

    def tri(self, x0, y0, x1, y1, x2, y2, c) -> "Canvas":
        def e(ax, ay, bx, by, px_, py_):
            return (bx - ax) * (py_ - ay) - (by - ay) * (px_ - ax)
        for y in range(math.floor(min(y0, y1, y2)), math.ceil(max(y0, y1, y2)) + 1):
            for x in range(math.floor(min(x0, x1, x2)), math.ceil(max(x0, x1, x2)) + 1):
                a, b, d = e(x0, y0, x1, y1, x, y), e(x1, y1, x2, y2, x, y), e(x2, y2, x0, y0, x, y)
                if (a >= 0 and b >= 0 and d >= 0) or (a <= 0 and b <= 0 and d <= 0):
                    self.px(x, y, c)
        return self

    def rows(self, x: int, y: int, rows: list[str], cmap: dict[str, str]) -> "Canvas":
        for j, row in enumerate(rows):
            for i, ch in enumerate(row):
                col = cmap.get(ch)
                if col:
                    self.px(x + i, y + j, col)
        return self

    def blit(self, o: "Canvas", x: int, y: int, flip: bool = False) -> "Canvas":
        for j in range(o.h):
            for i in range(o.w):
                c = o.p[j * o.w + i]
                if c:
                    self.px(x + (o.w - 1 - i if flip else i), y + j, c)
        return self

    def flip_x(self) -> "Canvas":
        o = Canvas(self.w, self.h)
        o.blit(self, 0, 0, True)
        return o

    def copy(self) -> "Canvas":
        o = Canvas(self.w, self.h)
        o.p = self.p[:]
        return o

    def tint(self, col: str, t: float) -> "Canvas":
        self.p = [c and mix(c, col, t) for c in self.p]
        return self

    def bbox(self) -> tuple[int, int, int, int]:
        x0, y0, x1, y1 = self.w, self.h, -1, -1
        for y in range(self.h):
            for x in range(self.w):
                if self.p[y * self.w + x]:
                    x0, x1, y0, y1 = min(x0, x), max(x1, x), min(y0, y), max(y1, y)
        return x0, y0, x1, y1

    def polish(self) -> "Canvas":
        """Silhouette light (top-left) and shadow (bottom-right), plus a cast shadow
        under any darker colour region above."""
        q, W, H = self.p[:], self.w, self.h

        def at(x, y):
            return q[y * W + x] if 0 <= x < W and 0 <= y < H else None

        for y in range(H):
            for x in range(W):
                c = q[y * W + x]
                if not c:
                    continue
                r = ramp(c)
                up, lf, dn, rt = at(x, y - 1), at(x - 1, y), at(x, y + 1), at(x + 1, y)
                o = c
                if not dn or not rt:
                    o = r[1]
                elif up and up != c and _lum(up) + 8 < _lum(c) and ramp(up)[2] != c:
                    o = r[1]
                elif not up or (not lf and not at(x - 1, y - 1)):
                    o = r[3]
                self.p[y * W + x] = o
        return self

    def outline(self, col: str | None = None, polish: bool = True) -> "Canvas":
        if col is None and polish:
            self.polish()
        q, W = self.p[:], self.w
        for y in range(self.h):
            for x in range(W):
                if q[y * W + x]:
                    continue
                n = None
                for dx, dy in ((0, 1), (0, -1), (1, 0), (-1, 0)):
                    xx, yy = x + dx, y + dy
                    if 0 <= xx < W and 0 <= yy < self.h and q[yy * W + xx]:
                        n = q[yy * W + xx]
                        break
                if n:
                    self.p[y * W + x] = col or mix(ramp(n)[0], "#1c0f22", 0.25)
        return self

    def image(self, scale: int = 1) -> Image.Image:
        im = Image.new("RGBA", (self.w, self.h), (0, 0, 0, 0))
        px = im.load()
        for y in range(self.h):
            for x in range(self.w):
                c = self.p[y * self.w + x]
                if c:
                    px[x, y] = (*hex_rgb(c), 255)
        if scale != 1:
            im = im.resize((self.w * scale, self.h * scale), Image.NEAREST)
        return im


def fit(sprite: Canvas, w: int, h: int, bottom: int | None = None) -> Canvas:
    """Centre `sprite`'s opaque box horizontally in a w x h canvas; bottom-align it on
    row `bottom` (default the last row), or centre vertically when bottom is -1."""
    out = Canvas(w, h)
    x0, y0, x1, y1 = sprite.bbox()
    if x1 < 0:
        return out
    bw, bh = x1 - x0 + 1, y1 - y0 + 1
    ox = (w - bw) // 2 - x0
    if bottom == -1:
        oy = (h - bh) // 2 - y0
    else:
        oy = (h - 1 if bottom is None else bottom) - y1
    out.blit(sprite, ox, oy)
    return out


def save(im: Image.Image, root: Path, rel: str) -> None:
    path = root / rel
    path.parent.mkdir(parents=True, exist_ok=True)
    im.save(path, optimize=True)
