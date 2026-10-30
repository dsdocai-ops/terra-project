"""v3 UI kit: 9-slice frames for the Theme (StyleBoxTexture), drawn at 1x for the
320x180 UI grid. Each texture is N x N with a border of `margin` px."""

from __future__ import annotations

from .core import Canvas, ramp, rng

WOOD = ramp("#b8743a")
INK = "#3b1d0c"
PAPER = ("#c8a068", "#e8c890", "#f8e4b8", "#fff2d4")
BRASS = ramp("#f0c048")


def panel(n: int, b: int, out: str, band, inner: str, fill: str, grain: str | None = None, rivet: bool = False, seed: int = 3) -> Canvas:
    s, r = Canvas(n, n), rng(seed)
    for y in range(n):
        for x in range(n):
            e = min(x, y, n - 1 - x, n - 1 - y)
            if e == 0:
                c = out
            elif e < b - 1:
                top = y < b - 1 and y <= x and y <= n - 1 - x
                left = x < b - 1 and x < y and x < n - 1 - y
                c = band[1] if (y > n - b or x > n - b) and not top and not left else band[2]
                if e == 1 and (top or left):
                    c = band[3]
            elif e == b - 1:
                c = inner
            else:
                c = grain if grain and r() < 0.05 else fill
            s.px(x, y, c)
    for x, y in ((0, 0), (n - 1, 0), (0, n - 1), (n - 1, n - 1)):
        s.px(x, y, None)
    for x, y in ((1, 1), (n - 2, 1), (1, n - 2), (n - 2, n - 2)):
        s.px(x, y, out)
    if rivet:
        for x, y in ((2, 2), (n - 3, 2), (2, n - 3), (n - 3, n - 3)):
            s.px(x, y, BRASS[3])
    return s


GREEN = ramp("#5aa040")
FRAMES = {
    # name: (canvas, margin)
    "panel_wood": (panel(16, 5, INK, WOOD, WOOD[0], "#2b1b17", "#34221c", rivet=True), 5),
    "panel_paper": (panel(16, 5, INK, WOOD, WOOD[0], PAPER[2], PAPER[1], rivet=True), 5),
    "slot": (panel(12, 4, "#6a3e1a", (None, "#f0d6a0", "#c8a068", "#9a7040"), "#b08850", "#dcb880"), 4),
    "button": (panel(12, 4, INK, (None, WOOD[1], WOOD[2], WOOD[3]), WOOD[1], WOOD[2]), 4),
    "button_hover": (panel(12, 4, INK, (None, WOOD[2], WOOD[3], WOOD[4]), WOOD[2], WOOD[3]), 4),
    "button_pressed": (panel(12, 4, INK, (None, WOOD[0], WOOD[1], WOOD[2]), WOOD[0], WOOD[1]), 4),
    "button_go": (panel(12, 4, "#14300c", (None, GREEN[1], GREEN[2], GREEN[3]), GREEN[1], GREEN[2]), 4),
}
