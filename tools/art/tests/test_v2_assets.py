"""v2 tiles and sprite sheets (art direction v2, D1/D2): sizes and layout the
game's TileSet and tools/make_sprite_frames.gd rely on, 4x nearest-neighbour
export, and every facing drawn (decision 2026-10-21)."""

from pathlib import Path

import pytest
from PIL import Image, ImageOps

import gen_sprites_v2
import gen_tiles_v2

REPO_ROOT = Path(__file__).resolve().parents[3]
COLUMNS = gen_sprites_v2.IDLE_FRAMES + gen_sprites_v2.WALK_FRAMES
ROWS = len(gen_sprites_v2.SUFFIXES)


@pytest.fixture(scope="module")
def built(tmp_path_factory: pytest.TempPathFactory) -> Path:
    root = tmp_path_factory.mktemp("v2")
    for biome in gen_tiles_v2.BIOMES:
        gen_tiles_v2.build(root, biome)
    gen_sprites_v2.build(root)
    return root


def _blocky(img: Image.Image, k: int) -> bool:
    rgba = img.convert("RGBA")
    small = rgba.resize((rgba.width // k, rgba.height // k), Image.NEAREST)
    return small.resize(rgba.size, Image.NEAREST).tobytes() == rgba.tobytes()


@pytest.mark.parametrize("biome", gen_tiles_v2.BIOMES)
def test_tile_atlas_is_three_64x96_cells_matching_tiles_gd(built: Path, biome: str) -> None:
    with Image.open(built / gen_tiles_v2.OUT_DIR / biome / "atlas.png") as img:
        assert img.size == (64 * 3, 96)
        assert _blocky(img, 4)
        rgba = img.convert("RGBA")
        # FLOOR (0,0): the 64x32 diamond fills rows 32..63 and nothing is above it.
        assert rgba.getpixel((32, 48))[3] == 255
        assert rgba.crop((0, 0, 64, 32)).getbbox() is None
        assert rgba.crop((0, 64, 64, 96)).getbbox() is None
        # WALL (1,0): its top face reaches row 0; PIT (2,0): only the footprint.
        assert rgba.getpixel((96, 2))[3] == 255
        assert rgba.crop((128, 0, 192, 32)).getbbox() is None


def test_the_game_tileset_uses_the_v2_cell_size() -> None:
    tres = (REPO_ROOT / "assets/tilesets/placeholder_iso.tres").read_text(encoding="utf-8")
    assert "collapsed_mines/atlas.png" in tres
    assert "texture_region_size = Vector2i(64, 96)" in tres


def _sheet(built: Path, rel: Path) -> Image.Image:
    return Image.open(built / rel).convert("RGBA")


@pytest.mark.parametrize("who", gen_sprites_v2.PLAYERS)
def test_player_sheets_are_8_rows_of_64x96_frames(built: Path, who: str) -> None:
    img = _sheet(built, gen_sprites_v2.PLAYER_DIR / f"{who}.png")
    assert img.size == (64 * COLUMNS, 96 * ROWS)
    assert _blocky(img, 4)
    for row in range(ROWS):
        for col in range(COLUMNS):
            cell = img.crop((col * 64, row * 96, (col + 1) * 64, (row + 1) * 96))
            box = cell.getbbox()
            assert box is not None, f"{who} row {row} col {col} is empty"
            assert box[3] == 96, f"{who} row {row} col {col}: boots end on the frame's last drawn row (92..95)"


@pytest.mark.parametrize("enemy_id", gen_sprites_v2.V2_ENEMIES)
def test_enemy_sheets_have_eight_drawn_rows(built: Path, enemy_id: str) -> None:
    img = _sheet(built, gen_sprites_v2.ENEMY_DIR / f"{enemy_id}_sheet.png")
    fw, fh = img.width // COLUMNS, img.height // ROWS
    assert (fw, fh) in ((64, 96), (64, 64)), enemy_id
    assert img.width == fw * COLUMNS and img.height == fh * ROWS
    assert _blocky(img, 4)
    for row in range(ROWS):
        assert img.crop((0, row * fh, fw, (row + 1) * fh)).getbbox() is not None, f"{enemy_id} row {row}"


def test_body_facings_are_drawn_not_mirrored(built: Path) -> None:
    img = _sheet(built, gen_sprites_v2.PLAYER_DIR / "wren.png")
    order = gen_sprites_v2.SUFFIXES

    def first(suffix: str) -> Image.Image:
        r = order.index(suffix)
        return img.crop((0, r * 96, 64, (r + 1) * 96))

    for east, west in (("e", "w"), ("se", "sw"), ("ne", "nw")):
        assert ImageOps.mirror(first(east)).tobytes() != first(west).tobytes(), (east, west)
    assert len({first(s).tobytes() for s in order}) == len(order), "every facing is a different drawing"


def test_idle_and_walk_frames_animate(built: Path) -> None:
    img = _sheet(built, gen_sprites_v2.PLAYER_DIR / "wren.png")
    frames = {img.crop((c * 64, 0, (c + 1) * 64, 96)).tobytes() for c in range(COLUMNS)}
    assert len(frames) >= 3


def test_v1_enemy_generator_leaves_v2_ids_alone(tmp_path: Path) -> None:
    import gen_enemies

    gen_enemies.build(tmp_path)
    written = {p.name for p in (tmp_path / gen_enemies.OUT_DIR).glob("*_sheet.png")}
    assert not written & {f"{e}_sheet.png" for e in gen_sprites_v2.V2_ENEMIES}
    assert len(written) == len(gen_enemies.ENEMIES) - len(gen_sprites_v2.V2_ENEMIES)
