# tools/art

Python generators for every pixel-art asset. The contract (palettes, sizes, outline and shading rules, naming, review step) is [SPEC-art-audio.md](../../specs/SPEC-art-audio.md). Dev-only: the game never runs Python.

| File | What it is |
|---|---|
| `requirements.txt` | Pillow, numpy, pytest (Python 3.12) |
| `palette.py` | Master palette: 8 hue ramps x 5 steps, 7 neutrals, 2 accents (`GLOBAL`), the 7 biome palettes (`biome(id)`, each with `ground_ramp`, `wall_ramp` and qualified `"<biome>.<name>"` accents), `MATERIAL` ramps (cloth, iron, timber, ...), `UI`, `RARITY`, `ELEMENT`, and `ALL` (every name a Canvas resolves). Generators take every color from here by name. v2 layer (art direction v2, D5): `V2_RAMPS` (`<ramp>_<n>`, 0 = lightest), `V2_CHARACTERS` + `CHARACTER_SLOTS` (BODY template palettes, `char_<who>_<slot>`), `V2_SETS` with `v2_colors(set_id)` / `v2_rgb(set_id)` for `ui`, `collapsed_mines`, `town` |
| `pixel.py` | Shared primitives: `Canvas` (indexed-color grid of palette names; `put`, `rect`, `line`, `ellipse`, `ellipse_shaded`, `polygon`, `blit`, `outline`, `save`), `outline`, `shade`, `dither`, `iso_diamond`, `iso_box`, `mirror_h` (symmetric props and UI only), `sheet`, `save_png`, `seeded`. v2: `hash01` (bit-for-bit the mockup hash), `iso_tile`, `iso_block`, `stone_face`, `plank_face`, `brick_base`, `shingle_roof`, `iso_window`, `iso_door`, `iso_house`, `circle`, `tri`, `quad`, `scatter`, `sprite_from_rows`, `oct_socket`, `export_scaled` |
| `palette_map.py` | Maps every color in `docs/art-direction/v2/mockup-src/` onto the v2 palette (exact, snapped, or deferred to a named task) and writes `docs/art-direction/v2/palette-map.md`; `--check` fails if the report is stale. A report, not a generator |
| `gen_font.py` | `assets/fonts/sinkhole_pixel.png` + `.fnt`, the 5x7 UI font (own work) |
| `gen_ui.py` | `assets/ui/icons/`: 8 status icons, 2 weapon icons, pointer, potion flask |
| `gen_icons.py` | `assets/sprites/icons/relics/` (20 relic icons) and the 5 pickup sprites under `assets/sprites/props/` |
| `gen_props.py` | Collapsed Mines props: chest, shrine, rope, breakable, mining node, gold pickup |
| `gen_character.py` | The miner sheet, 48x48, 8 drawn facings x (2 idle + 6 walk) |
| `gen_enemies.py` | The 27 base enemy sheets, same layout as the miner |
| `gen_tiles.py` | Floor, wall and pit atlas (3 x 64x64) per pit biome, drawn from that biome's palette only |
| `build_all.py` | Runs every registered generator. `--check` verifies the committed outputs |
| `capture.gd`, `capture_ui.gd/.tscn` | Godot scripts for in-engine review screenshots |
| `tests/` | pytest suite: palette against the spec, primitives, every generator (files, palette, determinism, 8 rows), `build_all` |

## Rules the tools enforce

- **Names, not RGB.** `Canvas.put` raises `KeyError` for anything that is not a palette name. Biome-only colors are `"collapsed_mines.lantern"` from any canvas, or bare `"lantern"` on a canvas built with `palette.colors_for("collapsed_mines")` (what `gen_tiles.py` does, so a tile cannot borrow another biome's color).
- **8 drawn directions.** Character, enemy and boss sheets draw every facing as its own row in `Facing.SUFFIXES` order (`s, sw, w, nw, n, ne, e, se`); nothing is mirrored at build or run time (decision 2026-10-21, Dev A). `mirror_h` exists for symmetric props and UI pieces.
- **No alpha, no blends.** Every opaque pixel is fully opaque and one of the generator's allowed colors; `build_all.py --check` fails otherwise. Ground shadows are a separate sprite, never baked into frames.
- **Deterministic.** Same inputs, same bytes (`pixel.seeded(name)` for any randomness).

## Commands

From the repo root:

```powershell
py -m pip install -r tools/art/requirements.txt   # once
py -m pytest tools/art                             # tests (about 90 s: every generator runs twice)
py tools/art/build_all.py                          # regenerate every generated asset into assets/
py tools/art/build_all.py --check                  # exit 1 if a committed file differs or a PNG is off-palette
py tools/art/gen_enemies.py rock_tick              # one generator, one id (each gen_*.py runs on its own)
py tools/art/palette_map.py                        # refresh the v2 mockup-to-palette report
```

After regenerating sheets or atlases, run `godot --headless --path . --import`; the `SpriteFrames` and `TileSet` resources (`tools/make_sprite_frames.gd`, `tools/make_placeholder_tileset.gd`) only need re-running when the sheet layout changes.

`--check` compares PNGs by decoded pixels, so a different Pillow or zlib version does not fail it, and every other output by bytes. A PNG fails the palette check if any non-transparent pixel uses a color outside the generator's declared palette.

## Adding a generator

1. Write `gen_<thing>.py` with a `build(root: Path)` that writes its files under `root` at their repo-relative paths (`assets/...`). Colors come from `palette.py` by name; a literal RGB is a review failure.
2. Register it in `build_all.GENERATORS` with its allowed colors, for example `palette.biome("collapsed_mines").rgb()` for a tile generator or `palette.all_rgb()` for one that spans biomes.
3. Run `build_all.py`, commit the generator and its output together, then run `--check`.
4. Make a review sheet under `docs/asset-review/week-N/` and add a row to `docs/asset-review/INDEX.md`.

## Palette changes

Spec-table colors are locked. A biome's ramp selection locks once its first real tileset is approved. After that, any edit is a human decision: record it in the changelog at the top of `palette.py` and in SPEC-art-audio.
