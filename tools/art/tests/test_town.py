"""The town art (W5-B7): ground atlas, the pit edge in four stages, 11 buildings x 4
states, props and Wren's portrait."""

from pathlib import Path

import pytest
from PIL import Image

import build_all
import gen_portraits
import gen_town
import palette


@pytest.fixture(scope="module")
def built(tmp_path_factory: pytest.TempPathFactory) -> Path:
    root = tmp_path_factory.mktemp("town")
    gen_town.build(root)
    gen_portraits.build(root)
    return root


def _opaque(path: Path) -> int:
    with Image.open(path) as img:
        return sum(1 for _, _, _, a in img.convert("RGBA").getdata() if a)


def test_eleven_buildings_in_four_states_at_128(built: Path) -> None:
    assert len(gen_town.BUILDINGS) == 11
    for name in gen_town.BUILDINGS:
        for label in gen_town.STATES:
            path = built / gen_town.SPRITE_DIR / f"{name}_{label}.png"
            assert path.is_file(), path.name
            assert Image.open(path).size == (128, 128)


def test_the_four_states_of_a_building_are_four_drawings(built: Path) -> None:
    for name in gen_town.BUILDINGS:
        pixels = {
            label: Image.open(built / gen_town.SPRITE_DIR / f"{name}_{label}.png").convert("RGBA").tobytes()
            for label in gen_town.STATES
        }
        assert len(set(pixels.values())) == 4, name


def test_buildings_grow_with_their_level(built: Path) -> None:
    for name in gen_town.BUILDINGS:
        sizes = [_opaque(built / gen_town.SPRITE_DIR / f"{name}_{label}.png") for label in gen_town.STATES]
        assert sizes[0] < sizes[2] < sizes[3] or sizes[0] < sizes[1] < sizes[2], (name, sizes)


def test_buildings_are_told_apart_by_roof_colour_or_material(built: Path) -> None:
    fingerprints = {
        name: Image.open(built / gen_town.SPRITE_DIR / f"{name}_rebuilt.png").convert("RGBA").tobytes()
        for name in gen_town.BUILDINGS
    }
    assert len(set(fingerprints.values())) == 11


def test_the_pit_edge_has_four_stages_and_shrinks(built: Path) -> None:
    counts = []
    for stage in range(4):
        path = built / gen_town.TILE_DIR / f"pit_edge_{stage}.png"
        assert Image.open(path).size == (256, 128)
        counts.append(_opaque(path))
    assert counts == sorted(counts, reverse=True) and len(set(counts)) == 4, counts


def test_the_ground_atlas_matches_the_tile_layout(built: Path) -> None:
    assert Image.open(built / gen_town.TILE_DIR / "atlas.png").size == (192, 64)


def test_town_tiles_stay_on_the_town_palette(built: Path) -> None:
    allowed = palette.biome("town").rgb()
    for png in (built / gen_town.TILE_DIR).glob("*.png"):
        assert not build_all._off_palette(png, allowed), png.name


def test_wren_portrait_is_96(built: Path) -> None:
    path = built / gen_portraits.OUT_DIR / "wren.png"
    assert Image.open(path).size == (96, 96)
    assert _opaque(path) > 2500


def test_town_generators_are_registered() -> None:
    """Since art direction v3, gen_v3 owns the town tiles, buildings and portraits."""
    names = {g.name for g in build_all.GENERATORS}
    assert "v3" in names
