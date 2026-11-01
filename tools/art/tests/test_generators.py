"""Every registered generator: writes its files, stays on its palette, is
deterministic, and sheets carry 8 drawn directions (decision 2026-10-21)."""

from pathlib import Path

import pytest
from PIL import Image

import build_all
import gen_character
import gen_enemies
import gen_sprites_v2
import gen_tiles
import gen_tiles_v2
import gen_ui
import gen_icons
import gen_props
import palette

FRAME = gen_character.FRAME
COLUMNS = gen_character.IDLE_FRAMES + gen_character.WALK_FRAMES
DIRECTIONS = 8


@pytest.fixture(scope="module")
def built(tmp_path_factory: pytest.TempPathFactory) -> Path:
    """Every generator run once into a fresh root."""
    root = tmp_path_factory.mktemp("build")
    build_all.build(root, build_all.GENERATORS)
    return root


def _pngs(root: Path) -> list[Path]:
    return sorted(root.rglob("*.png"))


def test_registry_covers_every_generator_module() -> None:
    names = {g.name for g in build_all.GENERATORS}
    # Art direction v3: gen_v3 supersedes the v1/v2 sprite, icon, prop, tile, town and portrait generators.
    assert names == {"font", "character:miner", "v3"}
    assert len(names) == len(build_all.GENERATORS), "generator names are unique"


def test_build_writes_the_expected_files(built: Path) -> None:
    assert (built / "assets/fonts/sinkhole_pixel.png").is_file()
    assert (built / "assets/fonts/sinkhole_pixel.fnt").is_file()
    assert (built / gen_character.OUT_REL).is_file()
    for enemy_id in gen_enemies.ENEMIES:
        assert (built / gen_enemies.OUT_DIR / f"{enemy_id}_sheet.png").is_file(), enemy_id
    for biome in gen_tiles.BIOMES:
        assert (built / gen_tiles.OUT_DIR / biome / "atlas.png").is_file(), biome
    for name in gen_ui.ICONS:
        assert (built / gen_ui.OUT_DIR / f"{name}.png").is_file(), name
    for name in gen_icons.RELICS:
        assert (built / gen_icons.RELIC_DIR / f"{name}.png").is_file(), name
    for name in gen_icons.PICKUPS:
        assert (built / gen_icons.PROP_DIR / f"pickup_{name}.png").is_file(), name
    for name in gen_props.PROPS:
        assert (built / gen_props.OUT_DIR / f"{name}.png").is_file(), name


def test_twenty_seven_enemies_and_six_biomes() -> None:
    assert len(gen_enemies.ENEMIES) == 27
    assert len(gen_tiles.BIOMES) + len(gen_tiles_v2.BIOMES) == 6 and "town" not in gen_tiles.BIOMES
    assert not set(gen_tiles.BIOMES) & set(gen_tiles_v2.BIOMES)


@pytest.mark.parametrize("generator", build_all.GENERATORS, ids=lambda g: g.name)
def test_every_png_stays_on_its_palette(generator: build_all.Generator, tmp_path: Path) -> None:
    generator.run(tmp_path)
    pngs = _pngs(tmp_path)
    assert pngs, "generator wrote nothing"
    for png in pngs:
        off = build_all._off_palette(png, generator.allowed_colors)
        assert off == [], f"{png.relative_to(tmp_path).as_posix()}: {[build_all._hex(c) for c in off]}"


def test_no_png_has_semi_transparent_pixels(built: Path) -> None:
    for png in _pngs(built):
        with Image.open(png) as img:
            alphas = {a for _, (_, _, _, a) in img.convert("RGBA").getcolors(1 << 24)}
        assert alphas <= {0, 255}, png.relative_to(built).as_posix()


def test_build_is_deterministic(built: Path, tmp_path: Path) -> None:
    build_all.build(tmp_path, build_all.GENERATORS)
    first = {p.relative_to(built): p.read_bytes() for p in built.rglob("*") if p.is_file()}
    second = {p.relative_to(tmp_path): p.read_bytes() for p in tmp_path.rglob("*") if p.is_file()}
    assert first.keys() == second.keys()
    differing = sorted(str(k) for k in first if first[k] != second[k])
    assert differing == []


def test_check_is_clean_right_after_build(built: Path) -> None:
    assert build_all.check(built, build_all.GENERATORS) == []


def test_character_and_enemy_sheets_draw_all_eight_directions(built: Path) -> None:
    sheets = [built / gen_character.OUT_REL] + [built / gen_enemies.OUT_DIR / f"{e}_sheet.png" for e in gen_enemies.ENEMIES]
    for sheet_path in sheets:
        with Image.open(sheet_path) as img:
            fw, fh = img.width // COLUMNS, img.height // DIRECTIONS
            assert (fw * COLUMNS, fh * DIRECTIONS) == img.size and fw in (FRAME, 64) and fh in (FRAME, 64, 96), sheet_path.name
            rgba = img.convert("RGBA")
            for row in range(DIRECTIONS):
                cell = rgba.crop((0, row * fh, fw, (row + 1) * fh))
                assert cell.getbbox() is not None, f"{sheet_path.name} row {row} is empty"


def test_facing_rows_are_distinct_drawings_not_mirrors() -> None:
    """w (row 2) is not the mirror of e (row 6): each facing is its own drawing."""
    from PIL import ImageOps

    rows = gen_character.rows()
    west = rows[2][0].to_image()
    east = rows[6][0].to_image()
    assert ImageOps.mirror(east).tobytes() != west.tobytes()
    assert east.tobytes() != west.tobytes()


def test_tile_atlas_layout_matches_tiles_gd(built: Path) -> None:
    for biome in gen_tiles.BIOMES:
        with Image.open(built / gen_tiles.OUT_DIR / biome / "atlas.png") as img:
            assert img.size == (gen_tiles.CELL * 3, gen_tiles.CELL * 2)
            rgba = img.convert("RGBA")
            for row in range(2):
                for column in range(3):
                    box = (column * gen_tiles.CELL, row * gen_tiles.CELL, (column + 1) * gen_tiles.CELL, (row + 1) * gen_tiles.CELL)
                    assert rgba.crop(box).getbbox() is not None, (biome, column, row)
            # Every floor diamond occupies rows 16..47 of its cell and nothing above.
            floors = []
            for column, row in gen_tiles.FLOOR_VARIANT_CELLS:
                floor = rgba.crop((column * gen_tiles.CELL, row * gen_tiles.CELL, (column + 1) * gen_tiles.CELL, (row + 1) * gen_tiles.CELL))
                assert floor.getbbox()[1] >= gen_tiles.CY - gen_tiles.HALF_H, (biome, column, row)
                floors.append(floor.tobytes())
            assert len(set(floors)) == gen_tiles.FLOOR_VARIANTS, "%s floor variants differ" % biome


def test_tile_colors_come_from_the_biome_palette_only(tmp_path: Path) -> None:
    """The v1 tile generator (no longer registered since v3) still keeps to its biome palette."""
    for biome in gen_tiles.BIOMES:
        gen_tiles.build(tmp_path, biome)
        allowed = palette.biome(biome).rgb()
        png = tmp_path / gen_tiles.OUT_DIR / biome / "atlas.png"
        assert build_all._off_palette(png, allowed) == [], biome


def test_font_atlas_is_pure_white_and_fnt_lists_every_glyph(built: Path) -> None:
    import gen_font

    with Image.open(built / "assets/fonts/sinkhole_pixel.png") as img:
        colors = {c[:3] for _, c in img.convert("RGBA").getcolors(1 << 24) if c[3] > 0}
    assert colors == {(255, 255, 255)}
    fnt = (built / "assets/fonts/sinkhole_pixel.fnt").read_text(encoding="ascii")
    assert f"chars count={len(gen_font.G)}" in fnt
    assert fnt.count("\nchar id=") == len(gen_font.G)
