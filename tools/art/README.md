# tools/art

Python generators for every pixel-art asset. The contract (palettes, sizes, outline and shading rules, naming, review step) is [SPEC-art-audio.md](../../specs/SPEC-art-audio.md). Dev-only: the game never runs Python.

| File | What it is |
|---|---|
| `requirements.txt` | Pillow, numpy, pytest (Python 3.12) |
| `palette.py` | Master palette: 8 hue ramps x 5 steps, 7 neutrals, 2 accents (`GLOBAL`), the 7 biome palettes (`biome(id)`), `UI`, `RARITY`, `ELEMENT`. Generators take every color from here by name |
| `pixel.py` | Shared primitives (`Canvas`, `outline`, `shade`, `dither`, `iso_diamond`, `iso_box`, `mirror_h`, `sheet`, `save_png`). Stub until W2-A11 |
| `build_all.py` | Runs every registered generator. `--check` verifies the committed outputs |
| `tests/` | pytest suite |

Week 1 has no generators. Placeholders still come from `tools/make_placeholders.gd` and `tools/make_placeholder_tileset.gd`.

## Commands

From the repo root:

```powershell
python -m pip install -r tools/art/requirements.txt   # once
python -m pytest tools/art                             # tests
python tools/art/build_all.py                          # regenerate every generated asset into assets/
python tools/art/build_all.py --check                  # exit 1 if a committed file differs or a PNG is off-palette
```

`--check` compares PNGs by decoded pixels, so a different Pillow or zlib version does not fail it, and every other output by bytes. A PNG fails the palette check if any non-transparent pixel uses a color outside the generator's declared palette.

## Adding a generator

1. Write `gen_<thing>.py` with a function that takes an output root and writes its files at their repo-relative paths (`assets/...`). Colors come from `palette.py` by name; a literal RGB is a review failure.
2. Register it in `build_all.GENERATORS` with its allowed colors, for example `palette.biome("collapsed_mines").rgb()`.
3. Run `build_all.py`, commit the generator and its output together, then run `--check`.
4. Make a review sheet under `docs/asset-review/week-N/` and add a row to `docs/asset-review/INDEX.md`.

## Palette changes

Spec-table colors are locked. A biome's ramp selection locks once its first real tileset is approved. After that, any edit is a human decision: record it in the changelog at the top of `palette.py` and in SPEC-art-audio.
