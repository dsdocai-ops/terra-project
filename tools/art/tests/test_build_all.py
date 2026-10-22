"""build_all.py: build and --check against fake generators in a temp repo,
plus the real script on the real repo."""

import subprocess
import sys
from pathlib import Path

from PIL import Image

import build_all
import palette
from build_all import Generator
from conftest import ART_DIR, REPO_ROOT

OUTLINE = palette.rgb(palette.ACCENT["outline"])
FLASH = palette.rgb(palette.ACCENT["hit_flash"])
ALLOWED = frozenset({OUTLINE, FLASH})
SPRITE = "assets/sprites/common/fake.png"


def _png_writer(pixels: dict[tuple[int, int], tuple[int, int, int, int]], rel: str = SPRITE):
    def run(out_root: Path) -> None:
        img = Image.new("RGBA", (4, 4), (0, 0, 0, 0))
        for xy, rgba in pixels.items():
            img.putpixel(xy, rgba)
        path = out_root / rel
        path.parent.mkdir(parents=True, exist_ok=True)
        img.save(path)

    return run


def _fake(pixels=None, name: str = "fake", rel: str = SPRITE) -> Generator:
    pixels = pixels if pixels is not None else {(0, 0): (*OUTLINE, 255), (1, 1): (*FLASH, 255)}
    return Generator(name=name, allowed_colors=ALLOWED, run=_png_writer(pixels, rel))


def test_empty_registry_checks_clean(tmp_path: Path) -> None:
    assert build_all.check(tmp_path, ()) == []
    assert build_all.main(["--check"], root=tmp_path, generators=()) == 0


def test_build_writes_outputs_into_root(tmp_path: Path) -> None:
    written = build_all.build(tmp_path, (_fake(),))
    assert written == [Path(SPRITE)]
    assert (tmp_path / SPRITE).is_file()


def test_build_is_deterministic(tmp_path: Path) -> None:
    build_all.build(tmp_path / "a", (_fake(),))
    build_all.build(tmp_path / "b", (_fake(),))
    assert (tmp_path / "a" / SPRITE).read_bytes() == (tmp_path / "b" / SPRITE).read_bytes()


def test_check_clean_after_build(tmp_path: Path) -> None:
    build_all.build(tmp_path, (_fake(),))
    assert build_all.check(tmp_path, (_fake(),)) == []
    assert build_all.main(["--check"], root=tmp_path, generators=(_fake(),)) == 0


def test_check_flags_missing_committed_file(tmp_path: Path) -> None:
    problems = build_all.check(tmp_path, (_fake(),))
    assert len(problems) == 1
    assert "missing" in problems[0] and SPRITE in problems[0]
    assert build_all.main(["--check"], root=tmp_path, generators=(_fake(),)) == 1


def test_check_flags_changed_pixels(tmp_path: Path) -> None:
    build_all.build(tmp_path, (_fake(),))
    edited = _fake({(0, 0): (*OUTLINE, 255), (2, 2): (*FLASH, 255)})
    problems = build_all.check(tmp_path, (edited,))
    assert len(problems) == 1
    assert "differs" in problems[0] and SPRITE in problems[0]


def test_check_ignores_png_encoding_differences(tmp_path: Path) -> None:
    build_all.build(tmp_path, (_fake(),))
    committed = tmp_path / SPRITE
    Image.open(committed).save(committed, compress_level=0)
    assert build_all.check(tmp_path, (_fake(),)) == []


def test_check_flags_off_palette_color(tmp_path: Path) -> None:
    off = _fake({(0, 0): (*OUTLINE, 255), (3, 3): (255, 0, 255, 255)})
    build_all.build(tmp_path, (off,))
    problems = build_all.check(tmp_path, (off,))
    assert len(problems) == 1
    assert "outside palette" in problems[0] and "#FF00FF" in problems[0]


def test_check_ignores_fully_transparent_pixels(tmp_path: Path) -> None:
    clear = _fake({(0, 0): (*OUTLINE, 255), (3, 3): (255, 0, 255, 0)})
    build_all.build(tmp_path, (clear,))
    assert build_all.check(tmp_path, (clear,)) == []


def test_check_compares_non_png_outputs_by_bytes(tmp_path: Path) -> None:
    def writer(text: str):
        def run(out_root: Path) -> None:
            path = out_root / "assets/tilesets/fake/atlas.json"
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(text, encoding="utf-8")

        return run

    build_all.build(tmp_path, (Generator("json", ALLOWED, writer('{"a": 1}')),))
    problems = build_all.check(tmp_path, (Generator("json", ALLOWED, writer('{"a": 2}')),))
    assert len(problems) == 1 and "differs" in problems[0]


def test_check_flags_two_generators_writing_one_path(tmp_path: Path) -> None:
    gens = (_fake(name="one"), _fake(name="two"))
    build_all.build(tmp_path, gens[:1])
    problems = build_all.check(tmp_path, gens)
    assert any("written by both" in p for p in problems)


def test_real_repo_check_exits_zero() -> None:
    result = subprocess.run(
        [sys.executable, str(ART_DIR / "build_all.py"), "--check"],
        cwd=REPO_ROOT,
        capture_output=True,
        text=True,
        check=False,
    )
    assert result.returncode == 0, result.stdout + result.stderr


def test_pixel_stub_exposes_spec_api() -> None:
    import pixel

    for name in ("Canvas", "outline", "shade", "dither", "iso_diamond", "iso_box", "mirror_h", "sheet", "save_png"):
        assert callable(getattr(pixel, name)), name
