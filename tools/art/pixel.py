"""Small pixel-art toolkit shared by every generator (SPEC-art-audio).

A Canvas is a grid of RGBA pixels drawn with hard edges only: no anti-aliasing,
no blending except where a function says so. Output is always saved with nearest
neighbour so the engine's nearest filter shows exactly what was drawn.
"""
import math
import os
import random

from PIL import Image

import palette


class Canvas:
    def __init__(self, width, height):
        self.w = width
        self.h = height
        self.img = Image.new("RGBA", (width, height), palette.CLEAR)
        self.px = self.img.load()

    # --- primitives ---------------------------------------------------------
    def put(self, x, y, color):
        x = int(x)
        y = int(y)
        if 0 <= x < self.w and 0 <= y < self.h:
            self.px[x, y] = color

    def get(self, x, y):
        if 0 <= x < self.w and 0 <= y < self.h:
            return self.px[x, y]
        return palette.CLEAR

    def rect(self, x0, y0, x1, y1, color):
        for y in range(int(y0), int(y1) + 1):
            for x in range(int(x0), int(x1) + 1):
                self.put(x, y, color)

    def line(self, x0, y0, x1, y1, color):
        x0, y0, x1, y1 = int(round(x0)), int(round(y0)), int(round(x1)), int(round(y1))
        dx, dy = abs(x1 - x0), -abs(y1 - y0)
        sx = 1 if x0 < x1 else -1
        sy = 1 if y0 < y1 else -1
        err = dx + dy
        while True:
            self.put(x0, y0, color)
            if x0 == x1 and y0 == y1:
                break
            e2 = 2 * err
            if e2 >= dy:
                err += dy
                x0 += sx
            if e2 <= dx:
                err += dx
                y0 += sy

    def ellipse(self, cx, cy, rx, ry, color):
        for y in range(int(cy - ry) - 1, int(cy + ry) + 2):
            for x in range(int(cx - rx) - 1, int(cx + rx) + 2):
                u = (x + 0.5 - cx) / rx
                v = (y + 0.5 - cy) / ry
                if u * u + v * v <= 1.0:
                    self.put(x, y, color)

    def ellipse_shaded(self, cx, cy, rx, ry, ramp, light=(-0.6, -0.8)):
        """Fills an ellipse using a light->dark ramp lit from `light`."""
        for y in range(int(cy - ry) - 1, int(cy + ry) + 2):
            for x in range(int(cx - rx) - 1, int(cx + rx) + 2):
                u = (x + 0.5 - cx) / rx
                v = (y + 0.5 - cy) / ry
                if u * u + v * v <= 1.0:
                    lit = u * light[0] + v * light[1]  # >0 faces the light
                    if lit > 0.55:
                        c = ramp[0]
                    elif lit > -0.1:
                        c = ramp[1]
                    elif lit > -0.6:
                        c = ramp[2]
                    else:
                        c = ramp[3]
                    self.put(x, y, c)

    def polygon(self, points, color):
        """Scanline fill of a convex or simple polygon."""
        ys = [p[1] for p in points]
        for y in range(int(math.floor(min(ys))), int(math.ceil(max(ys))) + 1):
            xs = []
            n = len(points)
            for i in range(n):
                (xa, ya), (xb, yb) = points[i], points[(i + 1) % n]
                if ya == yb:
                    continue
                yc = y + 0.5
                if min(ya, yb) <= yc < max(ya, yb):
                    xs.append(xa + (yc - ya) * (xb - xa) / (yb - ya))
            xs.sort()
            for i in range(0, len(xs) - 1, 2):
                for x in range(int(math.floor(xs[i] + 0.5)), int(math.floor(xs[i + 1] + 0.5))):
                    self.put(x, y, color)

    # --- passes -------------------------------------------------------------
    def outline(self, color=palette.OUTLINE):
        """Adds a 1px outline on every transparent pixel next to an opaque one."""
        marks = []
        for y in range(self.h):
            for x in range(self.w):
                if self.px[x, y][3] != 0:
                    continue
                for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                    if self.get(x + dx, y + dy)[3] != 0:
                        marks.append((x, y))
                        break
        for x, y in marks:
            self.px[x, y] = color

    def blit(self, other, ox, oy):
        for y in range(other.h):
            for x in range(other.w):
                c = other.px[x, y]
                if c[3] != 0:
                    self.put(ox + x, oy + y, c)

    def save(self, path):
        os.makedirs(os.path.dirname(path), exist_ok=True)
        self.img.save(path)


def seeded(name):
    """A reproducible RNG per asset so re-running a generator is byte-identical."""
    return random.Random(sum(ord(c) * (i + 1) for i, c in enumerate(name)))


def sheet(frames, columns):
    rows = (len(frames) + columns - 1) // columns
    out = Canvas(frames[0].w * columns, frames[0].h * rows)
    for i, frame in enumerate(frames):
        out.blit(frame, (i % columns) * frame.w, (i // columns) * frame.h)
    return out
