"""palette.py v2 layer (SPEC-art-audio "Art direction v2", D5) against the
approved mockups in docs/art-direction/v2/ and the spec text."""

import re

import pytest

import palette
import palette_map
import pixel
from conftest import REPO_ROOT

SPEC = (REPO_ROOT / "specs" / "SPEC-art-audio.md").read_text(encoding="utf-8")
MOCKUP = REPO_ROOT / "docs" / "art-direction" / "v2" / "mockup-src"
HEX = re.compile(r"#[0-9A-Fa-f]{6}\b")


def _v2_paragraph() -> str:
    return next(line for line in SPEC.splitlines() if line.startswith("v2 layer (D5):"))


def _mockup_body_rows() -> list[str]:
    text = (MOCKUP / "lib2.js").read_text(encoding="utf-8")
    body = re.search(r"const BODY=\[(.*?)\];", text).group(1)
    return re.findall(r'"([^"]+)"', body)


def test_v2_names_are_well_formed_and_resolve_through_all() -> None:
    for name, value in palette.V2.items():
        assert re.fullmatch(r"[a-z0-9_]+", name), name
        assert re.fullmatch(r"#[0-9A-F]{6}", value), (name, value)
        assert palette.ALL[name] == value
    assert set(palette.V2.values()) <= set(palette.all_hex())


def test_v2_ramps_do_not_repeat_within_a_ramp_and_read_light_to_dark() -> None:
    unordered = {"rarity_v2", "flowers", "danger"}
    for name, steps in palette.V2_RAMPS.items():
        assert len(set(steps)) == len(steps), name
        if name in unordered or len(steps) < 2:
            continue
        luma = [sum(w * c for w, c in zip((0.299, 0.587, 0.114), palette.rgb(h), strict=True)) for h in steps]
        assert luma[0] >= luma[-1], f"{name} should run light -> dark"


def test_v1_tables_are_untouched_by_the_v2_layer() -> None:
    assert len(palette.GLOBAL) == 8 * 5 + 7 + 2
    assert not set(palette.V2) & set(palette.NAMED)


def test_v2_ramp_helper() -> None:
    assert palette.v2_ramp("lamp") == tuple(f"lamp_{i}" for i in range(6))
    with pytest.raises(KeyError):
        palette.v2_ramp("not_a_ramp")


@pytest.mark.parametrize("set_id", list(palette.V2_SETS))
def test_v2_sets_resolve_on_their_own_canvas(set_id: str) -> None:
    colors = palette.v2_colors(set_id)
    c = pixel.Canvas(len(colors), 1, colors)
    for x, name in enumerate(colors):
        c.put(x, 0, name)
    assert c.rgb_set() == palette.v2_rgb(set_id)
    with pytest.raises(KeyError):
        palette.v2_colors("fungal_caverns")


def test_ui_set_cannot_reach_world_ramps() -> None:
    colors = palette.v2_colors("ui")
    assert "lamp_2" in colors and "mine_stone_0" not in colors and "grass_0" not in colors


@pytest.mark.parametrize("who", list(palette.V2_CHARACTERS))
def test_body_template_draws_every_character(who: str) -> None:
    rows = _mockup_body_rows()
    assert len(rows) == 21 and {len(r) for r in rows} == {14}
    assert set("".join(rows)) - {"."} <= set(palette.CHARACTER_CHARS)
    sprite = pixel.sprite_from_rows(rows, palette.character(who))
    assert {n for _, _, n in sprite.cells()} <= {f"char_{who}_{s}" for s in palette.CHARACTER_SLOTS}


def test_character_palettes_match_the_mockup() -> None:
    text = (MOCKUP / "lib2.js").read_text(encoding="utf-8")
    pw = dict(re.findall(r"(\w):'(#[0-9A-Fa-f]{6})'", re.search(r"const PW=\{(.*?)\};", text).group(1)))
    wren = dict(zip(palette.CHARACTER_CHARS, palette.V2_CHARACTERS["wren"], strict=True))
    assert {k: v.upper() for k, v in pw.items()} == wren


def test_mockup_ui_ramps_are_exact_v2_colors() -> None:
    # The palette-ramp table drawn on the UI atlas board (Main.part.html).
    text = (MOCKUP / "Main.part.html").read_text(encoding="utf-8")
    table = re.search(r"const ramps=\[(.*?)\];", text).group(1)
    values = set(palette.V2.values())
    missing = sorted({h.upper() for h in HEX.findall(table)} - values)
    assert missing == []


def test_spec_names_every_v2_ui_ramp() -> None:
    para = _v2_paragraph()
    for name in palette.V2_SETS["ui"]:
        assert f"`{name}`" in para, name
    # Every plain identifier the paragraph names is a real ramp or color name.
    named = set(re.findall(r"`([a-z][a-z0-9_]*)`", para))
    assert sorted(n for n in named if n not in palette.V2_RAMPS and n not in palette.V2) == []
    assert "`palette.V2_SETS`" in para


def test_palette_map_report_is_current_and_fully_assigned() -> None:
    rows = palette_map.classify()
    assert [r["hex"] for r in rows if r.get("task") == "unassigned"] == []
    assert palette_map.main(["--check"]) == 0
