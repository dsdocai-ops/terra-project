"""The miner: 48x48 frames, 8 facings x (2 idle + 6 walk) frames.

Sheet layout: one row per facing in Facing.SUFFIXES order (s, sw, w, nw, n, ne, e,
se), columns 0..1 idle, 2..7 walk. Every facing is drawn from its own angle;
nothing is mirrored (decision 2026-10-21, Dev A). Feet stand on frame row 41,
centre column 24. Another class is a palette and prop swap, not a new drawing.

Colors are palette names (palette.MATERIAL ramps and global steps). The ground
shadow is not baked in: it is the separate shadow sprite tinted by the biome
CanvasModulate (SPEC-art-audio, outline and shading rules).

    python tools/art/gen_character.py            writes assets/sprites/player/miner_sheet.png
"""

from __future__ import annotations

import math
from pathlib import Path

import palette
from pixel import Canvas, sheet

REPO_ROOT = Path(__file__).resolve().parents[2]
OUT_REL = Path("assets/sprites/player/miner_sheet.png")

FRAME = 48
# Facing.SUFFIXES order: s, sw, w, nw, n, ne, e, se (screen angles, y down).
SUFFIX_ANGLES = [90.0, 153.435, 180.0, 206.565, 270.0, 333.435, 0.0, 26.565]
IDLE_FRAMES = 2
WALK_FRAMES = 6

M = palette.MATERIAL
LAMP = "orange_light"
LAMP_GLOW = "yellow_highlight"


def facing_vectors(angle_deg: float) -> tuple[tuple[float, float], tuple[float, float]]:
    a = math.radians(angle_deg)
    d = (math.cos(a), math.sin(a))  # screen direction the miner faces (y down)
    # Ground plane is squashed 2:1 by the camera, so depth moves read half as far.
    return d, (-d[1], d[0])


def draw_frame(angle_deg: float, phase: float, moving: bool) -> Canvas:
    c = Canvas(FRAME, FRAME)
    d, s = facing_vectors(angle_deg)
    front = d[1] > 0.25     # faces the camera
    back = d[1] < -0.25     # faces away
    bob = abs(math.sin(phase)) * 1.6 if moving else (1 if phase > 0.5 else 0)
    swing = math.sin(phase) * 3.0 if moving else 0.0
    feet = (24, 41)

    # Legs: two stubs offset along the body's side axis, swinging along facing.
    for sign in (-1, 1):
        lx = feet[0] + s[0] * 3 * sign + d[0] * swing * sign
        ly = feet[1] + s[1] * 1.5 * sign + d[1] * swing * 0.5 * sign
        c.rect(lx - 1, ly - 5, lx + 1, ly - 1, M["cloth"][3])
        c.rect(lx - 1, ly - 1, lx + 2, ly, M["iron"][3])

    body_c = (24, 29 - bob)
    head_c = (24 + d[0] * 1.5, 18 - bob + d[1] * 1.0)

    # The pickaxe rides on the miner's right hand (side vector s).
    hand = (body_c[0] + s[0] * 8 + d[0] * 2, body_c[1] + s[1] * 3 + d[1] * 1 + 1 + (swing * 0.3))
    tool_top = (hand[0] + d[0] * 2 - s[0] * 1, hand[1] - 13)

    def draw_tool() -> None:
        c.line(hand[0], hand[1] + 3, tool_top[0], tool_top[1], M["timber"][1])
        c.line(hand[0] + 1, hand[1] + 3, tool_top[0] + 1, tool_top[1], M["timber"][2])
        hx, hy = tool_top
        for k in range(-3, 4):
            c.put(hx + k, hy + abs(k) // 2, M["iron"][1])
            c.put(hx + k, hy + abs(k) // 2 + 1, M["iron"][2])
        c.put(hx - 3, hy + 1, M["iron"][0])

    if back:
        draw_tool()

    # Torso with belt.
    c.ellipse_shaded(body_c[0], body_c[1], 7, 8, M["cloth"])
    for x in range(-6, 7):
        c.put(body_c[0] + x, body_c[1] + 3, M["timber"][3])
    c.put(body_c[0] + d[0] * 2, body_c[1] + 3, M["gold"][1])

    # Off-hand arm as a small skin blob on the other side.
    arm = (body_c[0] - s[0] * 7, body_c[1] + 1 - s[1] * 2 - swing * 0.3)
    c.ellipse_shaded(arm[0], arm[1], 2, 3, M["cloth"])
    c.ellipse_shaded(arm[0], arm[1] + 3, 1.6, 1.6, M["skin"])

    # Head.
    c.ellipse_shaded(head_c[0], head_c[1], 6, 6, M["skin"])
    if front:
        eye_y = head_c[1] + 0.5 + d[1]
        for sign in (-1, 1):
            ex = head_c[0] + d[0] * 2.5 + s[0] * 2.4 * sign
            c.put(ex, eye_y, "outline")
        c.put(head_c[0] + d[0] * 2.5, eye_y + 2.5, M["skin"][3])
    elif back:
        # Back of the head: hair under the helmet.
        c.ellipse(head_c[0], head_c[1] + 1.5, 5, 3, M["timber"][3])

    # Hard hat with the lamp on the facing side.
    c.ellipse_shaded(head_c[0], head_c[1] - 2.5, 7, 4.2, M["hat"])
    c.rect(head_c[0] - 7, head_c[1] - 0.5, head_c[0] + 6, head_c[1] + 0.5, M["hat"][2])
    lamp = (head_c[0] + d[0] * 5, head_c[1] - 2.5 + d[1] * 2)
    if not back:
        c.rect(lamp[0] - 1, lamp[1] - 1, lamp[0] + 1, lamp[1] + 1, M["iron"][1])
        c.put(lamp[0], lamp[1], LAMP_GLOW)
        c.put(lamp[0] + d[0] * 2, lamp[1] + d[1], LAMP)

    if not back:
        draw_tool()
    c.outline()
    return c


def rows() -> list[list[Canvas]]:
    """One row per facing: idle frames then walk frames."""
    out: list[list[Canvas]] = []
    for angle in SUFFIX_ANGLES:
        row = [draw_frame(angle, i, False) for i in range(IDLE_FRAMES)]
        row += [draw_frame(angle, math.pi * 2 * i / WALK_FRAMES, True) for i in range(WALK_FRAMES)]
        out.append(row)
    return out


def build(root: Path) -> Canvas:
    """Writes the miner sheet under root at its repo-relative path."""
    out = sheet(rows())
    out.save(Path(root) / OUT_REL)
    return out


if __name__ == "__main__":
    build(REPO_ROOT)
    print("character: miner")
