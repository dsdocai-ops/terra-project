"""Shared pixel-art primitives (specs/SPEC-art-audio.md, "Tools").

Stub. The API below is the contract generators are written against; bodies
land with the first generators in W2-A11. Every color argument is a palette
name from palette.py, never a literal RGB.
"""

from __future__ import annotations

from collections.abc import Mapping, Sequence
from pathlib import Path

_PENDING = "pixel.py primitives land in W2-A11"


class Canvas:
    """Indexed-color grid. Each cell holds a palette color name or None
    (transparent). Exported RGBA with a transparent background, no AA."""

    def __init__(self, width: int, height: int, colors: Mapping[str, str]) -> None:
        raise NotImplementedError(_PENDING)


def outline(canvas: Canvas, color: str = "outline") -> Canvas:
    """1 px outline around every opaque region (near-black #1A1420 by default)."""
    raise NotImplementedError(_PENDING)


def shade(canvas: Canvas, ramp: str, light_dir: tuple[int, int] = (-1, -1)) -> Canvas:
    """3 to 4 ramp steps, light from top-left: top faces highlight, right and bottom shadow."""
    raise NotImplementedError(_PENDING)


def dither(canvas: Canvas, a: str, b: str, region: tuple[int, int, int, int]) -> Canvas:
    """Checker dither between two palette colors. Tiles and bosses only."""
    raise NotImplementedError(_PENDING)


def iso_diamond(width: int = 64, height: int = 32) -> list[tuple[int, int]]:
    """Pixels of a 2:1 isometric floor diamond (Diamond Down)."""
    raise NotImplementedError(_PENDING)


def iso_box(width: int = 64, height: int = 64, top: int = 32) -> dict[str, list[tuple[int, int]]]:
    """Pixels of an iso wall block by face: "top", "left", "right"."""
    raise NotImplementedError(_PENDING)


def mirror_h(canvas: Canvas) -> Canvas:
    """Horizontal mirror, used for the w, nw, sw rows."""
    raise NotImplementedError(_PENDING)


def sheet(rows: Sequence[Sequence[Canvas]]) -> Canvas:
    """Packs frames into a sprite sheet: rows are drawn directions, columns frames."""
    raise NotImplementedError(_PENDING)


def save_png(canvas: Canvas, path: Path) -> None:
    """Writes RGBA PNG deterministically (same canvas, same bytes)."""
    raise NotImplementedError(_PENDING)
