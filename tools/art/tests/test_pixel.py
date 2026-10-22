"""pixel.py primitives: indexed-color canvas, passes, iso helpers, sheet
packing and deterministic export (SPEC-art-audio, "Testing")."""

from pathlib import Path

import pytest
from PIL import Image

import palette
import pixel
from pixel import Canvas


def _filled(w: int = 3, h: int = 3, color: str = "brown_base") -> Canvas:
    c = Canvas(w, h)
    c.rect(0, 0, w - 1, h - 1, color)
    return c


def test_canvas_starts_transparent_and_knows_palette_all() -> None:
    c = Canvas(4, 2)
    assert c.w == 4 and c.h == 2
    assert list(c.cells()) == []
    assert c.colors is palette.ALL


def test_put_get_and_offcanvas_ignored() -> None:
    c = Canvas(2, 2)
    c.put(1, 1, "outline")
    c.put(5, 5, "outline")
    c.put(-1, 0, "outline")
    assert c.get(1, 1) == "outline"
    assert c.get(5, 5) is None
    assert list(c.cells()) == [(1, 1, "outline")]


def test_unknown_name_raises_at_draw_time() -> None:
    c = Canvas(2, 2)
    with pytest.raises(KeyError):
        c.put(0, 0, "#FF00FF")
    with pytest.raises(KeyError):
        c.rect(0, 0, 1, 1, "not_a_color")
    with pytest.raises(KeyError):
        Canvas(2, 2, palette.biome("town").names).put(0, 0, "collapsed_mines.lantern")


def test_biome_canvas_resolves_bare_and_qualified_names() -> None:
    c = Canvas(2, 1, palette.colors_for("collapsed_mines"))
    c.put(0, 0, "lantern")
    c.put(1, 0, "collapsed_mines.lantern")
    img = c.to_image()
    assert img.getpixel((0, 0)) == img.getpixel((1, 0)) == (0xFF, 0xB3, 0x47, 255)


def test_rect_line_ellipse_polygon_cover_expected_cells() -> None:
    c = Canvas(8, 8)
    c.rect(1, 1, 3, 2, "neutral_0")
    assert len(list(c.cells())) == 6
    c = Canvas(8, 8)
    c.line(0, 0, 7, 7, "neutral_0")
    assert [(x, y) for x, y, _ in c.cells()] == [(i, i) for i in range(8)]
    c = Canvas(8, 8)
    c.ellipse(4, 4, 3, 3, "neutral_0")
    assert c.opaque(4, 4) and c.opaque(1.5, 4) and not c.opaque(0, 0)
    c = Canvas(8, 8)
    c.polygon([(0, 0), (8, 0), (8, 8), (0, 8)], "neutral_0")
    assert len(list(c.cells())) == 64


def test_ellipse_shaded_uses_only_the_four_ramp_steps_lit_from_top_left() -> None:
    ramp = palette.MATERIAL["cloth"]
    c = Canvas(16, 16)
    c.ellipse_shaded(8, 8, 6, 6, ramp)
    used = {name for _, _, name in c.cells()}
    assert used <= set(ramp)
    assert c.get(4, 4) == ramp[0], "top-left cap is the highlight"
    assert c.get(11, 11) == ramp[3], "bottom-right rim is the shadow"


def test_outline_rings_opaque_regions() -> None:
    c = Canvas(3, 3)
    c.put(1, 1, "brown_base")
    c.outline()
    ring = {(1, 0), (0, 1), (2, 1), (1, 2)}
    assert {(x, y) for x, y, n in c.cells() if n == "outline"} == ring
    assert c.get(0, 0) is None, "outline is 4-connected, not 8"
    # Function form returns a new canvas and leaves the input alone.
    base = Canvas(3, 3)
    base.put(1, 1, "brown_base")
    out = pixel.outline(base)
    assert len(list(base.cells())) == 1 and len(list(out.cells())) == 5


def test_shade_lights_from_top_left() -> None:
    ramp = palette.MATERIAL["rock"]
    c = _filled(3, 3, ramp[1])
    s = pixel.shade(c, ramp)
    assert s.get(1, 0) == ramp[0], "top edge takes the highlight"
    assert s.get(0, 1) == ramp[0], "left edge takes the highlight"
    assert s.get(1, 2) == ramp[2], "bottom edge takes the shadow"
    assert s.get(2, 1) == ramp[2], "right edge takes the shadow"
    assert s.get(1, 1) == ramp[1], "interior stays base"
    assert s.get(0, 0) == ramp[0] and s.get(2, 2) == ramp[2], "corners follow the light"
    assert c.get(1, 0) == ramp[1], "input untouched"
    lone = Canvas(1, 1)
    lone.put(0, 0, ramp[1])
    assert pixel.shade(lone, ramp).get(0, 0) == ramp[1], "open on both sides stays base"


def test_dither_checkers_two_colors_over_opaque_cells_only() -> None:
    c = _filled(4, 4, "brown_base")
    c.put(3, 3, None)
    d = pixel.dither(c, "brown_light", "brown_dark", (0, 0, 3, 3))
    assert d.get(0, 0) == "brown_light" and d.get(1, 0) == "brown_dark" and d.get(1, 1) == "brown_light"
    assert d.get(3, 3) is None


def test_iso_diamond_is_a_symmetric_2_to_1_diamond() -> None:
    cells = pixel.iso_diamond(64, 32)
    xs = {x for x, _ in cells}
    assert set(range(1, 63)) <= xs <= set(range(64))
    rows = {}
    for x, y in cells:
        rows.setdefault(y, []).append(x)
    assert max(len(r) for r in rows.values()) >= 62, "the middle rows span the cell"
    assert len(rows[0]) <= 4
    assert len(rows[0]) == len(rows[31]), "top and bottom rows match"
    assert all(0 <= y < 32 for _, y in cells)


def test_iso_box_faces_are_disjoint_and_sit_in_the_cell() -> None:
    faces = pixel.iso_box(64, 64, 32)
    top, left, right = (set(faces[k]) for k in ("top", "left", "right"))
    assert top and left and right
    assert not (top & left) and not (top & right) and not (left & right)
    assert all(x < 32 for x, _ in left) and all(x >= 32 for x, _ in right)
    assert max(y for _, y in top) < 32
    assert max(y for _, y in left) == 63


def test_mirror_h_flips_columns() -> None:
    c = Canvas(3, 1)
    c.put(0, 0, "red_base")
    m = pixel.mirror_h(c)
    assert m.get(2, 0) == "red_base" and m.get(0, 0) is None
    assert c.get(0, 0) == "red_base"


def test_sheet_packs_rows_as_directions_and_columns_as_frames() -> None:
    frames = []
    for i in range(3):
        f = Canvas(4, 4)
        f.put(i, 0, "red_base")
        frames.append(f)
    s = pixel.sheet([frames, frames[:2]])
    assert (s.w, s.h) == (12, 8)
    assert s.get(0, 0) == "red_base" and s.get(5, 0) == "red_base" and s.get(10, 0) == "red_base"
    assert s.get(5, 4) == "red_base" and s.get(10, 4) is None, "short rows are padded"


def test_sheet_rejects_mixed_frame_sizes_and_empty_input() -> None:
    with pytest.raises(ValueError):
        pixel.sheet([[Canvas(4, 4), Canvas(5, 4)]])
    with pytest.raises(ValueError):
        pixel.sheet([])


def test_save_png_is_deterministic_rgba_with_transparent_background(tmp_path: Path) -> None:
    c = Canvas(2, 2)
    c.put(0, 0, "outline")
    c.put(1, 1, "hit_flash")
    a, b = tmp_path / "a.png", tmp_path / "b.png"
    pixel.save_png(c, a)
    c.copy().save(b)
    assert a.read_bytes() == b.read_bytes()
    with Image.open(a) as img:
        assert img.mode == "RGBA"
        assert img.getpixel((0, 0)) == (0x1A, 0x14, 0x20, 255)
        assert img.getpixel((1, 1)) == (255, 255, 255, 255)
        assert img.getpixel((1, 0)) == (0, 0, 0, 0)
    assert c.rgb_set() == {(0x1A, 0x14, 0x20), (255, 255, 255)}


def test_seeded_rng_is_reproducible_per_name() -> None:
    assert pixel.seeded("floor").random() == pixel.seeded("floor").random()
    assert pixel.seeded("floor").random() != pixel.seeded("wall").random()


def test_palette_materials_and_ramps_are_global_names() -> None:
    for name, ramp in palette.MATERIAL.items():
        assert len(ramp) == 4, name
        assert set(ramp) <= set(palette.GLOBAL), name
    assert palette.ramp4("red") == ("red_light", "red_base", "red_dark", "red_shadow")
    assert palette.ramp4("red", high=True) == ("red_highlight", "red_light", "red_base", "red_dark")
    with pytest.raises(KeyError):
        palette.ramp4("pink")


@pytest.mark.parametrize("biome_id", palette.BIOME_IDS)
def test_biome_ramps_resolve_on_their_own_canvas(biome_id: str) -> None:
    b = palette.biome(biome_id)
    names = palette.colors_for(biome_id)
    for ramp in (b.ground_ramp, b.wall_ramp):
        assert len(ramp) == 4
        for name in ramp:
            assert name in names, (biome_id, name)
    assert b.ground_ramp[1] == b.qualified("ground") and b.wall_ramp[1] == b.qualified("wall")
    assert names[b.accent_1_ref] == b.accent_1
    assert names[b.light_ref] == b.light
    assert palette.ALL[b.accent_2_ref] == b.accent_2


def test_named_tables_do_not_collide() -> None:
    assert len(palette.NAMED) == len(palette.GLOBAL) + len(palette.UI) + len(palette.RARITY) + len(palette.ELEMENT)
    assert set(palette.ALL) >= set(palette.NAMED)
    assert "fungal_caverns.glow_cyan" in palette.ALL
