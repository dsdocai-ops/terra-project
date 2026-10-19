"""palette.py against specs/SPEC-art-audio.md.

The spec is parsed at test time, so a hex value edited in either place
without the other fails here rather than in review.
"""

import re

import pytest

import palette
from conftest import REPO_ROOT

SPEC = (REPO_ROOT / "specs" / "SPEC-art-audio.md").read_text(encoding="utf-8")
HEX = re.compile(r"#[0-9A-Fa-f]{6}\b")
NAMED_HEX = re.compile(r"([A-Za-z][A-Za-z -]*?)\s`(#[0-9A-Fa-f]{6})`")


def _biome_id(cell: str) -> str:
    return re.search(r"`(\w+)`", cell).group(1)


def _snake(name: str) -> str:
    return re.sub(r"[ -]+", "_", name.strip().lower())


def _biome_rows() -> list[list[str]]:
    rows = []
    for line in SPEC.splitlines():
        if not line.startswith("| `"):
            continue
        cells = [c.strip() for c in line.strip().strip("|").split("|")]
        if len(cells) == 7 and HEX.search(cells[2]):
            rows.append(cells)
    return rows


def _ui_line() -> str:
    return next(line for line in SPEC.splitlines() if line.startswith("UI palette:"))


def _segment(start: str, end: str | None) -> list[tuple[str, str]]:
    line = _ui_line()
    begin = line.index(start)
    stop = line.index(end) if end else len(line)
    return [(_snake(n), h.upper()) for n, h in NAMED_HEX.findall(line[begin:stop])]


BIOME_ROWS = _biome_rows()


def test_spec_tables_parsed() -> None:
    assert len(BIOME_ROWS) == 7
    assert len(_segment("UI palette:", "Rarity:")) == 7
    assert len(_segment("Rarity:", "Element tints")) == 6
    assert len(_segment("Element tints", None)) == 9


@pytest.mark.parametrize("row", BIOME_ROWS, ids=lambda r: _biome_id(r[0]))
def test_biome_matches_spec_row(row: list[str]) -> None:
    p = palette.biome(_biome_id(row[0]))
    assert p.mood == row[1]
    assert p.ground == HEX.search(row[2]).group().upper()
    assert p.wall == HEX.search(row[3]).group().upper()
    for cell, hex_value, name in (
        (row[4], p.accent_1, p.accent_1_name),
        (row[5], p.accent_2, p.accent_2_name),
        (row[6], p.light, p.light_name),
    ):
        spec_name, spec_hex = NAMED_HEX.search(cell).groups()
        assert name == _snake(spec_name)
        assert hex_value == spec_hex.upper()
        assert p.colors[name] == hex_value


def test_biome_ids_match_spec_order() -> None:
    assert palette.BIOME_IDS == tuple(_biome_id(r[0]) for r in BIOME_ROWS)


@pytest.mark.parametrize(
    ("table", "start", "end"),
    [
        ("UI", "UI palette:", "Rarity:"),
        ("RARITY", "Rarity:", "Element tints"),
        ("ELEMENT", "Element tints", None),
    ],
)
def test_named_tables_match_spec(table: str, start: str, end: str | None) -> None:
    assert getattr(palette, table) == dict(_segment(start, end))


def test_accents_match_spec() -> None:
    assert palette.ACCENT == {"hit_flash": "#FFFFFF", "outline": "#1A1420"}


def test_every_spec_hex_is_exposed() -> None:
    exposed = set(palette.all_hex())
    missing = sorted({h.upper() for h in HEX.findall(SPEC)} - exposed)
    assert missing == []


def test_global_set_shape() -> None:
    assert len(palette.RAMPS) == 8
    for ramp in palette.RAMPS.values():
        assert len(ramp) == len(palette.RAMP_STEPS) == 5
    assert len(palette.NEUTRAL) == 7
    expected = 8 * 5 + 7 + 2
    assert len(palette.GLOBAL) == expected
    assert len(set(palette.GLOBAL.values())) == expected, "global colors must be distinct"


@pytest.mark.parametrize("biome_id", palette.BIOME_IDS)
def test_biome_selection_rules(biome_id: str) -> None:
    p = palette.biome(biome_id)
    assert len(p.selection) == 24
    assert set(p.selection) <= set(palette.GLOBAL)
    assert {"outline", "hit_flash"} <= set(p.selection)
    assert 5 <= len(p.biome_only) <= 8
    assert not set(p.biome_only.values()) & set(palette.GLOBAL.values()), (
        "a biome-only color that already exists globally belongs in the selection"
    )
    assert len(p.colors) == len(p.selection) + len(p.biome_only)


def test_all_hex_values_well_formed() -> None:
    for value in palette.all_hex():
        assert re.fullmatch(r"#[0-9A-F]{6}", value), value


def test_rgb_conversion() -> None:
    assert palette.rgb("#1A1420") == (0x1A, 0x14, 0x20)
    assert palette.rgb_set(["#FFFFFF", "#1A1420"]) == {(255, 255, 255), (26, 20, 32)}


def test_unknown_biome_raises() -> None:
    with pytest.raises(KeyError):
        palette.biome("not_a_biome")
