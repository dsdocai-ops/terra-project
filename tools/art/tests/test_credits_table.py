"""CREDITS.md shape and addon font coverage. The full check of assets/ against
the table is tests/integration/test_credits.gd (W2-B7)."""

from pathlib import Path

from conftest import REPO_ROOT

CREDITS = REPO_ROOT / "CREDITS.md"
HEADER = ["Asset path", "Source URL", "Author", "License", "License URL", "Modifications"]
FONT_SUFFIXES = {".ttf", ".otf", ".woff", ".woff2", ".fnt"}


def _table() -> list[list[str]]:
    rows = []
    for line in CREDITS.read_text(encoding="utf-8").splitlines():
        if line.startswith("|"):
            rows.append([c.strip() for c in line.strip().strip("|").split("|")])
    return rows


def _row_globs() -> list[str]:
    return [row[0].strip("`") for row in _table()[2:]]


def test_header_has_six_schema_columns() -> None:
    table = _table()
    assert table[0] == HEADER
    assert all(set(cell) <= {"-"} for cell in table[1])
    assert all(len(row) == 6 for row in table)


def test_every_addon_font_has_a_row() -> None:
    fonts = [p for p in (REPO_ROOT / "addons").rglob("*") if p.suffix.lower() in FONT_SUFFIXES]
    globs = _row_globs()
    uncovered = [
        p.relative_to(REPO_ROOT).as_posix()
        for p in fonts
        if not any(Path(p.relative_to(REPO_ROOT).as_posix()).match(g) for g in globs)
    ]
    assert uncovered == []


def test_every_row_matches_a_file() -> None:
    for pattern in _row_globs():
        assert any(REPO_ROOT.glob(pattern)), pattern
