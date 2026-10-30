"""Regenerates every generated asset, or checks the committed ones.

    python tools/art/build_all.py            write every generator's output into the repo
    python tools/art/build_all.py --check    exit 1 if a committed file differs from fresh
                                             output or a PNG uses a color outside its palette

Generators register in GENERATORS. Each one writes its files under the root
it is given, at their repo-relative paths (assets/...). --check runs them into
a temp folder and compares: PNGs by decoded RGBA pixels (so a different zlib
or Pillow version does not fail the check), everything else by bytes.

Registered generators (2026-10-22): the UI font, UI icons, relic icons and
pickups, Collapsed Mines props, the miner sheet, the 27 base enemy sheets, the
six pit-biome tile atlases, the town ground and pit edge (town palette), the
town buildings and props, and the portraits. Tile generators are checked against their own
biome palette; everything else against palette.ALL.
"""

from __future__ import annotations

import argparse
import shutil
import sys
import tempfile
from collections.abc import Callable, Sequence
from dataclasses import dataclass
from pathlib import Path

from PIL import Image

ART_DIR = Path(__file__).resolve().parent
if str(ART_DIR) not in sys.path:
    sys.path.insert(0, str(ART_DIR))

import gen_character  # noqa: E402
import gen_enemies  # noqa: E402
import gen_font  # noqa: E402
import gen_icons  # noqa: E402
import gen_portraits  # noqa: E402
import gen_props  # noqa: E402
import gen_tiles  # noqa: E402
import gen_tiles_v2  # noqa: E402
import gen_sprites_v2  # noqa: E402
import gen_town  # noqa: E402
import gen_ui  # noqa: E402
import gen_v3  # noqa: E402
import palette  # noqa: E402

REPO_ROOT = ART_DIR.parents[1]
_MAX_LISTED_COLORS = 8


@dataclass(frozen=True)
class Generator:
    """name: shown in reports. allowed_colors: RGB tuples every opaque pixel
    of every PNG it writes must use (palette.biome(id).rgb() or a union of
    palette tables). run: writes the outputs under the given root."""

    name: str
    allowed_colors: frozenset[tuple[int, int, int]]
    run: Callable[[Path], None]


def _tile_v2_generator(biome_id: str) -> Generator:
    return Generator(
        name=f"tiles_v2:{biome_id}",
        allowed_colors=palette.v2_rgb(biome_id),
        run=lambda root, b=biome_id: gen_tiles_v2.build(root, b),
    )


def _tile_generator(biome_id: str) -> Generator:
    return Generator(
        name=f"tiles:{biome_id}",
        allowed_colors=palette.biome(biome_id).rgb(),
        run=lambda root, b=biome_id: gen_tiles.build(root, b),
    )


_FONT_COLORS = frozenset({palette.rgb(palette.ACCENT["hit_flash"])})

# Art direction v3 (2026-10-29): gen_v3 owns every player, enemy, portrait, icon,
# prop, town and tile output. The v1/v2 generators it supersedes (gen_ui,
# gen_icons, gen_props, gen_enemies, gen_sprites_v2, gen_tiles, gen_tiles_v2,
# gen_town, gen_portraits) stay importable and tested but are not registered, so
# their outputs are no longer checked against the committed files.
GENERATORS: tuple[Generator, ...] = (
    Generator("font", _FONT_COLORS, gen_font.build),
    Generator("character:miner", palette.all_rgb(), gen_character.build),
    Generator("v3", gen_v3.allowed_rgb(), gen_v3.build),
)


def _files_under(root: Path) -> list[Path]:
    return sorted(p.relative_to(root) for p in root.rglob("*") if p.is_file())


@dataclass(frozen=True)
class _Output:
    generator: Generator
    fresh: Path


def _generate(out_root: Path, generators: Sequence[Generator]) -> tuple[dict[Path, _Output], list[str]]:
    """Runs each generator into its own folder under out_root, then returns
    relative path -> output, plus problems for paths two generators both wrote."""
    outputs: dict[Path, _Output] = {}
    problems: list[str] = []
    for index, gen in enumerate(generators):
        gen_root = out_root / str(index)
        gen_root.mkdir(parents=True)
        gen.run(gen_root)
        for rel in _files_under(gen_root):
            if rel in outputs:
                problems.append(f"{rel.as_posix()}: written by both {outputs[rel].generator.name} and {gen.name}")
                continue
            outputs[rel] = _Output(gen, gen_root / rel)
    return outputs, problems


def build(root: Path, generators: Sequence[Generator] = GENERATORS) -> list[Path]:
    """Writes every generator's output into root. Returns the relative paths written."""
    with tempfile.TemporaryDirectory() as tmp:
        outputs, problems = _generate(Path(tmp), generators)
        if problems:
            raise RuntimeError("; ".join(problems))
        for rel, out in outputs.items():
            dest = root / rel
            dest.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(out.fresh, dest)
        return sorted(outputs)


def _rgba(path: Path) -> tuple[tuple[int, int], bytes]:
    with Image.open(path) as img:
        rgba = img.convert("RGBA")
        return rgba.size, rgba.tobytes()


def _off_palette(path: Path, allowed: frozenset[tuple[int, int, int]]) -> list[tuple[int, int, int]]:
    """Distinct RGB values of non-transparent pixels that are not in allowed."""
    with Image.open(path) as img:
        colors = img.convert("RGBA").getcolors(maxcolors=1 << 24) or []
    return sorted({(r, g, b) for _, (r, g, b, a) in colors if a > 0 and (r, g, b) not in allowed})


def _hex(color: tuple[int, int, int]) -> str:
    return "#{:02X}{:02X}{:02X}".format(*color)


def check(root: Path, generators: Sequence[Generator] = GENERATORS) -> list[str]:
    """Returns one problem string per failing file; empty means clean."""
    with tempfile.TemporaryDirectory() as tmp:
        outputs, problems = _generate(Path(tmp), generators)
        for rel, out in outputs.items():
            gen, fresh, name = out.generator, out.fresh, rel.as_posix()
            committed = root / rel
            if not committed.is_file():
                problems.append(f"{name}: missing (run build_all.py and commit the output) [{gen.name}]")
                continue
            if rel.suffix.lower() == ".png":
                same = _rgba(fresh) == _rgba(committed)
            else:
                same = fresh.read_bytes() == committed.read_bytes()
            if not same:
                problems.append(f"{name}: differs from fresh output of {gen.name}")
                continue
            if rel.suffix.lower() == ".png":
                off = _off_palette(committed, gen.allowed_colors)
                if off:
                    listed = ", ".join(_hex(c) for c in off[:_MAX_LISTED_COLORS])
                    more = f" (+{len(off) - _MAX_LISTED_COLORS} more)" if len(off) > _MAX_LISTED_COLORS else ""
                    problems.append(f"{name}: {len(off)} color(s) outside palette of {gen.name}: {listed}{more}")
        return problems


def main(
    argv: Sequence[str] | None = None,
    root: Path = REPO_ROOT,
    generators: Sequence[Generator] = GENERATORS,
) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--check", action="store_true", help="verify committed outputs instead of writing them")
    args = parser.parse_args(argv)

    if args.check:
        problems = check(root, generators)
        for problem in problems:
            print(f"FAIL {problem}")
        status = "FAILED" if problems else "OK"
        print(f"build_all --check: {len(generators)} generator(s), {len(problems)} problem(s): {status}")
        return 1 if problems else 0

    written = build(root, generators)
    print(f"build_all: {len(generators)} generator(s) wrote {len(written)} file(s)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
