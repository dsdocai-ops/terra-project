# Implementation Plan: Art direction v2

Status: **D1 to D7 accepted 2026-10-24** and recorded in SPEC-art-audio ("Art direction v2"), SPEC-ui-hud ("v2 theme") and CAPABILITY_MAP (AR-0). AR-1 and AR-2 done on `feat/art-audio-v2-pipeline`. First in-game pass landed early (2026-10-24, on request): AR-3 mines floor/wall/pit (`gen_tiles_v2.py`, TileSet cells 64x96), AR-7 BODY sheets for the four characters (Wren wired into `player.tscn`), AR-8 Hollow Miner, Rock Tick, Lantern Wisp (wired through the new `EnemyData.sprite_frames`) plus Goblin and Bat sheets. Review sheet pending in `docs/asset-review/INDEX.md`. Still to do in those tasks: props (AR-4), floor variants (needs a floor-generation hook), emissive masks, attack/hurt/death animations.

## Overview

The approved v2 mockups move the whole game to chunky, Stardew-density pixel art on the existing isometric 2:1 grid: textured stone and timber, plank-and-shingle buildings, layered trees, 1 px coloured outlines, and banded lantern lighting. The UI becomes pixel art on the same art grid, with a 3x5 bitmap font, 9-slice iron, brass, wood, parchment and ribbon frames, and a HUD rebuilt around those parts.

This plan ports the mockups into the real pipeline (`tools/art/` Python generators, `assets/`, `assets/ui/theme.tres`, `scenes/ui/`) in the order requested: art pipeline for tiles and sprites, bitmap font, 9-slice theme, then the HUD.

## Reference material (in the repo)

| Path | What it is |
|---|---|
| `docs/art-direction/v2/shots/*.png` | Approved renders: `main` (UI atlas), `menu`, `hud`, `shrine`, `dialogue`, `biomes` |
| `docs/art-direction/v2/mockup-src/lib.js` | Mockup kit, part 1: palette ramps, 3x5 font glyphs (`FG`), `frame`, `plank`, `parch`, `sock`, `bar`, `key`, `chain`, iso `dia`/`blk`, banded `lit()`, icon sprites |
| `docs/art-direction/v2/mockup-src/lib2.js` | Mockup kit, part 2: `BODY` character template and palettes, `house2`, `tree`, `bush`, `fence`, `barrel`, `crate`, `lamp`, `sign`, `well`, `stonePx`/`wallBlk`, `timberL/R`, `mineTex`, `cart`, `rubble`, `mush2`, `crystal2`, `pillar`, `candle`, `GOB`, `BAT2`, `sprLie` |
| `docs/art-direction/v2/mockup-src/*.part.html` | One file per board: layout coordinates and colours for every HUD, menu, shrine and dialogue element |

The mockup code is the drawing recipe, not shipping code. Each generator below ports one recipe to Python against `palette.py` names, which keeps the spec rules: names not RGB, deterministic, `build_all.py --check` clean.

## Decisions needed before work starts

| # | Decision | Recommendation | Why it needs a human | Owner |
|---|---|---|---|---|
| D1 | **World pixel scale.** Draw world art at quarter resolution (floor tile 16x8 art px) and export it scaled 4x with nearest neighbour, so tiles stay 64x32 and every world unit, speed and range is unchanged. | Yes | Changes how every world generator draws. The current miner and tiles are drawn at full resolution, which is why they look finer than the mockups. | Dev A |
| D2 | **Frame size table** (SPEC-art-audio "Sizes"). The mockup proportions need taller frames: humanoid 64x96 (16x24 art), feet at y=92; wall tile 64x96 (walls are about 20 art px high); tall prop 64x128; town building 192x192 per state; small enemy 48x48 (12x12 art); portrait stays 96x96; icons stay 16x16. | Yes | Locked spec values. Changes `make_sprite_frames.gd` offsets, `FacingSprite` and TileSet `texture_origin`. | Dev A (world), Dev B (town, portraits) |
| D3 | **UI pixel scale.** Draw UI on a 320x180 art grid and export it 3x, which fills the 960x540 viewport exactly. Existing `Control` layouts keep 960x540 coordinates on a 3 px snap. World art is 4 viewport px per art px and UI is 3. | Yes. Stardew also scales its UI separately from the world. | Layout positions must become multiples of 3. The alternative is a 240x135 UI grid at 4x, which would mean redoing the HUD layout. | Dev B |
| D4 | **Font.** Replace the 5x7 `sinkhole_pixel` with the mockup's 3x5 capitals-only font (own work, `gen_font.py`). Lowercase draws as capitals. Ship two faces: plain and pre-outlined (for damage numbers and world labels). Sizes 1x and 2x on the UI grid. | Yes | SPEC-ui-hud names an 8/16 px font. The 3x5 font is smaller and capitals-only. | Dev B |
| D5 | **Palette changes.** Add UI ramps (void, lamp, bone, wood, parchment, blood, echo), party colours (P2 teal `#3FC1B8`, P3 rose `#E879A6`, P4 lime `#A6D65A`; P1 uses lamp) and the mockup's school socket rims. Re-derive the `collapsed_mines` and `town` ramps from the mockups. Log each change in the `palette.py` changelog and in SPEC-art-audio. | Yes | Biome palettes lock once a tileset is approved. Collapsed Mines and town are already past that point. | Both |
| D6 | **Projection stays isometric 2:1.** Stardew is top-down. The mockups keep the design doc's isometric view and borrow only density and style. | Keep isometric | Design doc section 17. Recorded so it is not reopened by accident. | Both |
| D7 | **Banded lighting.** Port the mockup's 5-level, Bayer-dithered light banding as a full-screen canvas shader over the world (`assets/shaders/light_banding.gdshader`) on top of the existing `CanvasModulate` and `PointLight2D`. Emissive pixels (lamps, eyes, fuses, runes, lava) come from a per-sprite `_emissive.png` drawn unshaded above the lit layer. | Yes, behind a setting so it can be switched off | New shader plus a new emissive layer in the world tree. Needs a perf check in the Compatibility renderer. | Dev A |

If D1 or D2 is declined, Phase 2 and Phase 3 below need a re-plan. Phases 4 to 6 (font, theme, HUD) depend only on D3, D4 and D5.

## Environment note

Python 3.14 with Pillow 12, numpy and pytest is installed, but plain `python` on PATH hits the Microsoft Store stub. Use the `py` launcher (`py tools/art/build_all.py`, `py -m pytest tools/art`). The spec says 3.12. 3.14 runs the pipeline, so `requirements.txt` gets a note rather than a version pin change.

## Phases and tasks

Task ids follow `tasks/todo.md` (`W<week>-<lane><n>`). They are left as `AR-n` here until the humans place them in a week. Each task names its module id and lane.

### Phase 0: Lock the decisions (both lanes)

**AR-0 `[art-audio]` Record D1 to D7 in the specs.** SPEC-art-audio: sizes table, export scales, palette changelog, emissive layer, lighting. SPEC-ui-hud: theme section, font, UI grid. CAPABILITY_MAP: note on the art-audio row. `docs/asset-review/INDEX.md`: mark the week-5 sheets that v2 supersedes as `changes`.
- Accept: both devs approve the spec diff in review.
- Verify: `grep` that no spec still quotes 48x48 humanoid frames or the 5x7 font.

### Phase 1: Pipeline primitives (shared, blocks everything after it)

**AR-1 `[art-audio]` `pixel.py` v2 primitives.** Port from `lib.js`/`lib2.js`:
- Quarter-res iso: `iso_diamond(16x8)`, `iso_box(w, d, h)` with per-column face fill.
- Fills: `tri_fill`, `quad_fill`, `circle_fill`, `line`.
- Seeded scatter: `scatter(mask, density, fn, seed)`.
- Face textures: `stone_face` (the `stonePx` band-and-mortar pattern), `plank_face`, `shingle_roof`.
- Characters: `sprite_from_rows(rows, palette_map)` (the mockup's string-row sprites).
- Export: `export_scaled(canvas, k)` (nearest, k = 4 for world, 3 for UI).
- Accept: every primitive has a pytest (deterministic bytes, on-palette).
- Verify: `py -m pytest tools/art` green.

**AR-2 `[art-audio]` `palette.py` v2 (D5).** UI ramps, party colours, school rims, re-derived `collapsed_mines` and `town` ramps, changelog entry dated.
- Accept: the palette pytest passes. Every colour used in `mockup-src` is exact, snapped to a near v2 colour, or deferred to a named later task (`docs/art-direction/v2/palette-map.md`, zero unassigned).
- Verify: `py tools/art/palette_map.py --check` and `test_palette_v2.py`.
- Deferred: `data/palette.tres`. The spec lists it, but v1 never created it and nothing reads it yet. It needs a new Resource script under `scripts/data/` (ask first), so it lands with the first runtime consumer (AR-12 theme or AR-17 lighting).

### Phase 2: Tiles and world props (Dev A reviews)

**AR-3 `[art-audio]` `gen_tiles.py` v2, Collapsed Mines first.**
- Floor: 3 base tones × 8 baked texture variants (pebbles, cracks, dust, copper glints, from `mineTex`), so the scatter never visibly repeats.
- Walls: 64x96, stone-band texture with ore flecks, top cap.
- Timber support overlay tiles, pit edge, door frame and rail tiles (ties plus steel highlight).
- Atlas json carries variant weights for floor generation.
- Accept: review sheet plus an in-engine capture of a generated floor that matches `shots/hud.png` in density and colour. Dev A approves.
- Verify: `build_all.py --check` clean; `godot --headless --path . --import` with zero warnings; floor-generation tests still green.

**AR-4 `[art-audio]` `gen_props.py` v2 world props.** Crate, barrel, rubble cluster, minecart with ore, hanging lantern (plus emissive mask), rail end, mining node, shrine pedestal, pillar with brazier, candle cluster. These are the mockup's `crate`, `barrel`, `rubble`, `cart`, `hangLamp`, `pillar`, `candle` and `pedestal`.
- Accept: review sheet. Each prop has `<id>.png`, `<id>.json` and `<id>_emissive.png` where it glows.

**AR-5 `[art-audio]` `gen_town.py` v2 (Dev B reviews).**
- Ground: grass with tufts, clover and flowers; cobble plaza; dirt path.
- 11 buildings × 4 states at 192x192 (D2), using `house2`: plank walls on a stone base, shingle gable roof, framed windows with shutters, plank door, chimney with smoke, optional sign.
- Trees (3 sizes, fruiting variant), bushes, flower beds, fences, iron lamp post, signpost, well with the Watcher eyes, pit edge stages 0 to 3 with rocky rim.
- Accept: review sheet plus a town capture matching `shots/dialogue.png` and `shots/menu.png`.

**AR-6 `[art-audio]` Other five biome tilesets.** Same recipe, re-skinned per biome (fungal `mush2` caps, crystal `crystal2` spires, drowned water tiles, ember lava channel, heart veins). Each lands in that biome's content week (8 to 10), as SPEC-art-audio already schedules.

### Phase 3: Characters and enemies (Dev A reviews)

**AR-7 `[art-audio]` `BODY` template in `gen_character.py`.** 16x24 art frame exported at 64x96 (D2). The mockup only shows the south facing, so the other 7 facings and every animation frame (idle 4, run 6, attack, cast, dodge, hurt, downed, death) are new drawing work. The template must hold the same palette slots (helmet, lamp, hair, skin, jacket, strap, gloves, pants, boots) so Wren, Kestrel, Ivy, Brann and the NPC bodies are palette swaps plus small per-character overrides (Ivy's hair, Brann's beard).
- Accept: review sheet with all 8 rows, every animation labelled, south idle matching the mockup pixel for pixel. Dev A approves.
- Verify: `test_assets.gd` (8 drawn directions, frame counts); `make_sprite_frames.gd` re-run with the new frame size; player feet on the tile in an in-engine capture.

**AR-8 `[art-audio]` Biome 1 enemies redrawn.** Hollow Miner (BODY swap, pale skin, emissive eyes, torn clothes), Dynamite Goblin (`GOB`), Cave Bat (`BAT2`), Rock Tick and Lantern Wisp in the same style, all with emissive masks. Downed pose for players (`sprLie` reference, drawn properly per facing).

**AR-9 `[art-audio]` Portraits.** `gen_portraits.py` ports the 20x21 Hilde portrait recipe (exported 4x, centred in 96x96) and makes it the template for the other NPCs and the 4 characters.

### Phase 4: Bitmap font (Dev B reviews)

**AR-10 `[art-audio]` `gen_font.py` v2 (D4).**
- Glyphs: the mockup `FG` set (A to Z, 0 to 9, `.,!?':-+/%()<>×$·`, the down-arrow advance glyph) plus `&#[]"=*`.
- Variable width (M, N, W, K are 4 to 5 px), 1 px spacing, line height 7.
- Exported 3x as BMFont `.fnt` + `.png`: `assets/fonts/sinkhole_3x5.fnt` and `sinkhole_3x5_outline.fnt` (pre-baked 1 px near-black outline, so outlining doesn't depend on engine font outlines).
- Lowercase maps to uppercase glyphs in the `.fnt`.
- The old `sinkhole_pixel` stays until AR-12 switches the theme, then it is removed in the same PR.
- Accept: review sheet showing every glyph at 1x and 3x, plus a capture of a label, a button and a damage number.
- Verify: font pytest (glyph count, determinism); Godot import with zero warnings.

### Phase 5: 9-slice theme (Dev B reviews)

**AR-11 `[art-audio]` `gen_ui.py` v2 pieces**, all on the UI grid and exported 3x into `assets/ui/`:

| Piece | Mockup source | 9-slice margins (art px) |
|---|---|---|
| `panel_iron`, `panel_brass` (selected), `panel_violet` (cursed) | `frame()` with corner rivets | 4 |
| `plank` (wood board, nails) | `plank()` | 3 |
| `parchment` (torn edge) | `parch()` | 3 |
| `ribbon_banner` with tails | Shrine `ribbon()` | 4 (tails as separate sprites) |
| `tag_chip` (synergy and modifier labels) | HUD `tag()` | 2 |
| `keycap` | `key()` | 2 |
| `socket_18`, `socket_24` octagons × rim sets (bronze, school colours, party colours, rarity) | `sock()` | not 9-slice |
| `relic_slot` × 5 rarities | HUD relic strip | 2 |
| Bars: HP with heart cap and chip layer, class resource, teammate, boss bar with skull caps and phase ticks | `bar()` plus HUD | 2 |
| Lantern cursor, chain, dialogue advance arrow, enemy-count skull | `SP.lantern`, `chain()`, `_`, `SP.skull` | not 9-slice |

- Accept: atlas review sheet laid out like `shots/main.png`. Dev B approves.
- Verify: `build_all.py --check` clean; every piece on-palette.

**AR-12 `[ui-hud]` `assets/ui/theme.tres` v2.**
- `StyleBoxTexture` for `Panel`, `PanelContainer`, `Button` (normal = iron, hover/focus = brass, pressed = brass sunk 3 px, disabled = dim iron), `LineEdit`, `ProgressBar`, `TooltipPanel`, `PopupPanel`.
- Font `sinkhole_3x5` at 15 px (1x) and 30 px (2x title); colours: bone text, ash secondary, lamp accent.
- Type variations: `PlankPanel`, `ParchmentPanel`, `RibbonLabel`, `TagChip`, `KeyCap`, `DamageNumber` (outline font), `NameTag`.
- Replaces the current `StyleBoxFlat` panel.
- Accept: every existing UI scene still opens. Capture of the lobby, choice popup and dialogue box in the new theme.
- Verify: `test_ui_scenes.gd` green; manual readability at 960x540 and 1920x1080 (spec requirement).

### Phase 6: HUD rebuild (Dev B, `ui-hud`)

Same `HudModel` bindings, same signals, presentation only (no sync changes). Each widget is rebuilt to `shots/hud.png`, reusing the existing widget scripts where one exists:

| Widget | Existing script | v2 change |
|---|---|---|
| Player plate: wood plank, brass portrait socket, name and class, HP bar with heart cap, 10-HP ticks, chip-damage layer, class resource bar | `lantern_orb.gd` | Replace the orb with the plate. The orb's chip logic carries over. |
| Teammate stack: socket rimmed in party colour, name, bar, downed X with countdown | `teammate_badge.gd` | Restyle; downed state from `RunPlayerState` |
| Floor sign: plank on chains, floor and biome, modifier tag hanging below, enemies-left skull | `floor_sign.gd` | Restyle; add modifier tag and counter |
| Pip's map: parchment, ink rooms, current room in red, `$ ! R T` glyphs, dotted unexplored rooms | `lamp_map.gd` | Redraw onto parchment; `FloorLayout` binding unchanged |
| Currency column, right-aligned, icons at 2x | `currency_readout.gd` | Restyle |
| Pickup feed, right side, coloured per source | (new, small) | Bind to `currency_gained` and `relic_picked` events |
| Synergy tags and relic strip with rarity frames | `relic_rope.gd`, `status_row.gd` | Tags as `TagChip`, relics in `relic_slot` |
| Action bar on a plank: Q R V sockets rimmed by school, cooldown overlay with seconds, ult socket with fill and glow, class skill, active relic, keycaps under each | `ability_row.gd` | Restyle; cooldown math unchanged |
| Weapon card on a plank: large icon, weapon name, heavy-attack name, swap hint, potion count | `weapon_diamond.gd` | Replace the diamond with the card |
| World-space: damage numbers (outline font, crits at 2x, element colours), name tags in party colour, enemy mini-bars | combat-core pool (theme only) | Theme styles only; `combat-core` keeps the pool |

**AR-13 `[ui-hud]` Plate, teammates, floor sign, currencies, feed.**
**AR-14 `[ui-hud]` Action bar, weapon card, relic strip, synergies.**
**AR-15 `[ui-hud]` Pip's map minimap.**
**AR-16 `[ui-hud]` World-space text styles** (theme plus a small PR into `combat-core` for the font hook, reviewed by Dev A).

For each HUD task:
- Accept: an in-engine capture next to `shots/hud.png` with the same parts in the same places, at 960x540 and 1920x1080.
- Verify:
  - `test_ui_scenes.gd` and `test_hud_model.gd` green.
  - New unit tests for chip-damage timing, cooldown text and the downed countdown.
  - Two-instance smoke (`--host` / `--join`) confirming the client HUD shows the host's truth for HP, a downed teammate, currencies and a relic pick.
  - Run the game as the last step (team habit).

### Phase 7: Lighting and world integration (Dev A)

**AR-17 `[biomes]` Banded lighting and emissive layer (D7).**
- `light_banding.gdshader` on a `BackBufferCopy` over the world `CanvasLayer`: 5 luminance bands with a 4x4 Bayer threshold.
- Emissive sprites on a layer above it, drawn unshaded.
- Per-biome `CanvasModulate` and `PointLight2D` values taken from the mockups (ambient per biome, lantern radius about 90 art px × 4).
- Setting toggle in `PlayerProfile.settings`.
- Accept: capture of Collapsed Mines floor 1 next to `shots/hud.png`. Perf: 60 FPS with 16 lights and 60 units in the perf scene.
- Verify: perf scene; the screenshot comparison.

### Phase 8: Menus, shrine and dialogue screens (Dev B, after AR-12)

**AR-18 `[ui-hud]` Main menu v2:**
- Pixel logo as a generated sprite.
- Menu list with lantern cursor and selected bar.
- Key hints.
- Night town and pit backdrop from AR-5.

**AR-19 `[ui-hud]` Choice popup v2:**
- Ribbon title.
- Rows with rarity sockets, the selected row in brass with a lantern cursor.
- Tags and synergy hint.
- Co-op "is eyeing" line.

**AR-20 `[story-dialogue]` Dialogue box theme v2:**
- Wooden frame with parchment fill and ink text.
- Red ribbon name plate.
- Portrait that breaks the frame, with a sunset backdrop.
- Advance arrow.

## Dependency order and parallel work

```
AR-0 decisions
 ├─ AR-1 primitives ─┬─ AR-3 tiles ── AR-6 other biomes (weeks 8 to 10)
 │                   ├─ AR-4 props ── AR-17 lighting
 │                   ├─ AR-5 town
 │                   ├─ AR-7 BODY ── AR-8 enemies, AR-9 portraits
 │                   ├─ AR-10 font ─┐
 │                   └─ AR-11 UI pieces ── AR-12 theme ── AR-13..16 HUD ── AR-18..20 screens
 └─ AR-2 palette (with AR-1)
```

- After AR-1 and AR-2, the Pit lane (AR-3, AR-4, AR-7, AR-8, AR-17) and the Surface lane (AR-5, AR-9 to AR-16, AR-18 to AR-20) touch separate files and can run in parallel.
- AR-16 touches `combat-core`. Its font hook is a small cross-lane PR.
- Every asset task follows the review step in SPEC-art-audio. Placeholders stay until each sheet is approved, so the build stays playable throughout.

## Suggested placement in the schedule

The current branch is week 6. A sketch for the humans to adjust:

| When | Pit lane (Dev A reviews) | Surface lane (Dev B reviews) |
|---|---|---|
| Rest of week 6 | AR-0 (both), AR-1, AR-2 | AR-10 font, AR-11 UI pieces |
| Week 7 | AR-3 mines tiles, AR-4 props, AR-7 BODY | AR-12 theme, AR-13 to AR-15 HUD, AR-5 town |
| Week 8 | AR-8 enemies, AR-17 lighting, AR-6 fungal and crystal | AR-16, AR-18 to AR-20, AR-9 portraits |
| Weeks 9 and 10 | AR-6 remaining biomes in their content weeks | polish from review feedback |

This adds work to weeks 6 to 8 that the week plan did not contain. Week-5 and week-6 placeholder and real assets get redone in v2 style rather than cut. Nothing in the design doc's inventory is reduced.

## Risks

| Risk | Impact | Mitigation |
|---|---|---|
| The mockups show only the south-facing still for each character. 7 more facings and every animation frame are new drawing work. | High: the biggest single cost | `BODY` palette slots make the 4 characters, NPCs and humanoid enemies one sheet design plus swaps. Draw facings once on the template. |
| The 4x world and 3x UI scales sit side by side. | Low | Accepted in D3. Both are integer, so no shimmer. |
| The banding shader costs frame time in the Compatibility renderer. | Medium | Setting toggle; perf gate in AR-17; fall back to smooth light if it misses 60 FPS. |
| Palette changes to already-approved biomes. | Medium | Recorded human decision (D5) with changelog. Old sheets are marked `changes` in INDEX, not deleted until replaced. |
| The capitals-only 3x5 font hurts long text such as lore pages. | Medium | 2x size for long text. A lowercase 5x7 face stays possible for lore only, decided at AR-10 review. |
| `python` resolves to the Store stub. | Low | Use `py` (see Environment note). |
| `build_all.py --check` fails while assets are mid-migration. | Low | Each generator lands with its outputs in one PR, as the README requires. |

## Open questions for the humans

1. Approve D1 to D7, or say which to change.
2. Place the AR tasks in weeks (the table above is a sketch).
3. Should the old 5x7 font stay for lore and long text (AR-10)?
