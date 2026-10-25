"""pixel.py v2 primitives (art direction v2, SPEC-art-audio "Art direction v2"):
quarter-resolution iso helpers, face textures, the house recipe, scatter,
string-row sprites, sockets and scaled export."""

from pathlib import Path

import pytest

import pixel
from pixel import Canvas

STONE = {"a": "brown_base", "b": "brown_dark", "c": "brown_light", "hi": "brown_highlight", "lo": "brown_shadow", "m": "neutral_0"}

HOUSE = {
    "wall_l": "orange_base", "wall_l_line": "orange_dark", "wall_r": "brown_light", "wall_r_line": "brown_base",
    "base_stone": "neutral_4", "base_stone_alt": "neutral_3", "base_mortar": "neutral_2",
    "base_stone_r": "neutral_3", "base_stone_alt_r": "neutral_2", "base_mortar_r": "neutral_1",
    "edge_dark": "brown_shadow", "edge_light": "orange_highlight",
    "roof": "red_base", "roof_stripe": "red_dark", "roof_hi": "red_light", "roof_edge": "red_shadow", "roof_back": "red_dark", "roof_outline": "outline",
    "frame": "neutral_6", "cross": "neutral_5", "glass": "blue_dark", "glass_hi": "blue_light", "sill": "brown_base", "shutter": "green_dark",
    "door_a": "brown_base", "door_b": "brown_dark", "door_frame": "brown_shadow", "step": "neutral_4", "knob": "yellow_light",
    "chimney": "neutral_3", "chimney_side": "neutral_2", "chimney_cap": "neutral_1",
}


@pytest.mark.parametrize(
    ("a", "b", "expected"),
    [(0, 0, 0.0), (1, 2, 0.8830856902059168), (3, 5, 0.09490608680061996), (-7, 11, 0.46906405314803123),
     (123456, -98765, 0.7660055821761489), (2.9, -3.9, 0.09034410980530083)],
)
def test_hash01_matches_the_mockup_hash(a: float, b: float, expected: float) -> None:
    # Reference values from the mockup's JavaScript hs(a, b).
    assert pixel.hash01(a, b) == pytest.approx(expected, abs=1e-15)


def test_iso_tile_is_the_16x8_diamond_with_bevels() -> None:
    c = Canvas(20, 10)
    pixel.iso_tile(c, 10, 1, "brown_base")
    rows = [sum(1 for x in range(20) if c.opaque(x, y)) for y in range(1, 9)]
    assert rows == [4, 8, 12, 16, 16, 12, 8, 4]
    c = Canvas(20, 10)
    pixel.iso_tile(c, 10, 1, "brown_base", hi="brown_light", lo="brown_dark")
    names = {n for _, _, n in c.cells()}
    assert names == {"brown_base", "brown_light", "brown_dark"}
    assert c.get(8, 1) == "brown_light" and c.get(11, 8) == "brown_dark"


def test_iso_block_draws_both_faces_and_a_raised_top() -> None:
    c = Canvas(20, 30)
    pixel.iso_block(c, 10, 20, 12, "neutral_5", "neutral_3", "neutral_1")
    assert c.get(2, 24) == "neutral_3"  # left face, bottom row of its first column
    assert c.get(17, 24) == "neutral_1"  # right face, bottom row of its last column
    assert c.get(2, 25) is None
    assert c.get(10, 9) == "neutral_5"  # top diamond, raised by h
    assert c.get(10, 3) is None


def test_iso_block_accepts_texture_functions_counted_from_the_bottom() -> None:
    c = Canvas(20, 30)
    seen: list[int] = []

    def left(px: int, r: int) -> str:
        seen.append(r)
        return "neutral_0" if r == 0 else "neutral_3"

    pixel.iso_block(c, 10, 20, 6, "neutral_5", left, "neutral_1")
    assert sorted(set(seen)) == list(range(6))
    # The bottom row of the left face sits on the floor diamond's lower-left edge.
    assert c.get(2, 24) == "neutral_0"
    assert c.get(2, 23) == "neutral_3"


def test_stone_face_has_mortar_courses_and_is_deterministic() -> None:
    f = pixel.stone_face(STONE, seed=3)
    assert all(f(px, 0) == "neutral_0" for px in range(30))
    assert all(f(px, 4) == "neutral_0" for px in range(30))
    assert {f(px, r) for px in range(60) for r in range(12)} <= set(STONE.values())
    g = pixel.stone_face(STONE, seed=3)
    assert [f(px, r) for px in range(40) for r in range(12)] == [g(px, r) for px in range(40) for r in range(12)]
    with pytest.raises(KeyError):
        pixel.stone_face({"a": "brown_base"}, seed=1)


def test_stone_face_ore_flecks_are_rare() -> None:
    f = pixel.stone_face({**STONE, "ore": "orange_light"}, seed=5)
    cells = [f(px, r) for px in range(400) for r in range(24)]
    share = cells.count("orange_light") / len(cells)
    assert 0 < share < 0.05


def test_plank_face_lines_and_foundation() -> None:
    base = pixel.brick_base("neutral_4", "neutral_3", "neutral_2")
    f = pixel.plank_face("orange_base", "orange_dark", h=16, foundation=base)
    assert f(0, 2) == "neutral_2"  # foundation mortar row
    assert f(5, 15) == "orange_base"
    assert f(5, 13) == "orange_dark"  # (16 - 13) % 3 == 0
    assert {f(px, r) for px in range(20) for r in range(16)} == {"orange_base", "orange_dark", "neutral_4", "neutral_3", "neutral_2"}


def test_circle_is_symmetric() -> None:
    c = Canvas(11, 11)
    pixel.circle(c, 5, 5, 4, "green_base")
    cells = {(x, y) for x, y, _ in c.cells()}
    assert cells == {(10 - x, y) for x, y in cells} == {(x, 10 - y) for x, y in cells}
    assert (5, 1) in cells and (5, 0) not in cells


def test_shingle_roof_stays_on_palette_and_inside_its_quad() -> None:
    c = Canvas(40, 30)
    pixel.shingle_roof(c, (4, 24), (28, 26), (34, 6), (10, 4), "red_base", "red_dark")
    assert {n for _, _, n in c.cells()} == {"red_base", "red_dark"}
    assert not c.opaque(0, 0) and not c.opaque(39, 29)


def test_iso_house_is_deterministic_and_uses_only_its_palette() -> None:
    def draw() -> Canvas:
        c = Canvas(64, 56)
        pixel.iso_house(c, 32, 18, 3, 2, 16, 11, HOUSE, windows_left=(0.2, 0.6), door_right=0.4, chimney=0.3)
        return c

    a, b = draw(), draw()
    assert a.grid == b.grid
    assert {n for _, _, n in a.cells()} <= set(HOUSE.values())
    assert {"glass", "door_a", "chimney"} <= {k for k, v in HOUSE.items() if v in {n for _, _, n in a.cells()}}


def test_iso_house_rejects_an_incomplete_palette() -> None:
    with pytest.raises(KeyError):
        pixel.iso_house(Canvas(10, 10), 5, 5, 1, 1, 4, 3, {"wall_l": "orange_base"})


def test_scatter_is_deterministic_and_respects_the_mask() -> None:
    def run() -> list[tuple[int, int]]:
        c = Canvas(40, 20)
        hits: list[tuple[int, int]] = []

        def fn(canvas: Canvas, x: int, y: int, t: float, n: int) -> None:
            hits.append((x, y))
            canvas.put(x, y, "neutral_0")

        pixel.scatter(c, 200, fn, seed=7, mask=lambda x, y: x < 20)
        return hits

    first = run()
    assert first == run()
    assert first and all(x < 20 for x, _ in first)


def test_sprite_from_rows_maps_characters_and_validates() -> None:
    c = pixel.sprite_from_rows([".o.", "oYo"], {"o": "outline", "Y": "yellow_base"})
    assert (c.w, c.h) == (3, 2)
    assert c.get(0, 0) is None and c.get(1, 0) == "outline" and c.get(1, 1) == "yellow_base"
    with pytest.raises(ValueError):
        pixel.sprite_from_rows(["..", "..."], {})
    with pytest.raises(KeyError):
        pixel.sprite_from_rows(["Z"], {"o": "outline"})


def test_oct_socket_has_cut_corners_and_a_well() -> None:
    c = pixel.oct_socket(18, ("yellow_base", "yellow_highlight", "yellow_dark"), "neutral_0", "neutral_1")
    assert (c.w, c.h) == (18, 18)
    assert c.get(0, 0) is None and c.get(17, 17) is None
    assert c.get(9, 0) == "outline"
    assert c.get(9, 9) == "neutral_0"
    with pytest.raises(ValueError):
        pixel.oct_socket(8, ("a", "b", "c"), "neutral_0", "neutral_1")


@pytest.mark.parametrize("k", [3, 4])
def test_export_scaled_is_blocky_nearest_neighbour(k: int, tmp_path: Path) -> None:
    c = Canvas(3, 2)
    c.put(0, 0, "outline")
    c.put(2, 1, "yellow_base")
    s = pixel.export_scaled(c, k)
    assert (s.w, s.h) == (3 * k, 2 * k)
    assert all(s.get(x, y) == "outline" for x in range(k) for y in range(k))
    assert s.get(k, 0) is None
    assert all(s.get(2 * k + x, k + y) == "yellow_base" for x in range(k) for y in range(k))
    s.save(tmp_path / "a.png")
    pixel.export_scaled(c, k).save(tmp_path / "b.png")
    assert (tmp_path / "a.png").read_bytes() == (tmp_path / "b.png").read_bytes()
    with pytest.raises(ValueError):
        pixel.export_scaled(c, 0)
