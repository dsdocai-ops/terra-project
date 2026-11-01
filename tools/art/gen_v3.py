"""Art direction v3 (the "Rules" art bible): every player, enemy, portrait, icon,
prop, town building and tile atlas, redrawn in the hand-pixeled Stardew-style pass
and written over the v1/v2 outputs at the same paths and layouts.

Layouts kept so no scene, SpriteFrames or TileSet has to change shape:
  players/<who>.png            512x768: 8 facings x (2 idle + 6 walk), 64x96 frames, feet on row 92
  enemies/<id>_sheet.png       humanoids 512x768 (64x96), others 512x512 (64x64), feet 4 px above the frame bottom
  portraits/<id>.png           96x96
  icons/relics/<id>.png        16x16 (all 88 relics), icons/abilities/<id>.png 18x18 (all 38 rune stones)
  ui/icons/*.png               16x16 (status, weapons, pointer, potion)
  ui/frames/*.png              9-slice StyleBoxTexture sources for assets/ui/theme.tres
  props/*.png, town/*.png      dungeon and town props, buildings in 4 states (128x128)
  tilesets/<biome>/atlas.png   FLOOR, WALL, PIT, 3 floor variants (scripts/tiles.gd order)

v3 colours are derived, not palette names: each material is one base colour and
v3.core.ramp() derives its outline, shadow, light and shine tones. The allowed colour
set for build_all --check is therefore the set this generator emits (allowed_rgb()).

    py tools/art/gen_v3.py
"""

from __future__ import annotations

import sys
import tempfile
from functools import lru_cache
from pathlib import Path

from PIL import Image

ART_DIR = Path(__file__).resolve().parent
if str(ART_DIR) not in sys.path:
    sys.path.insert(0, str(ART_DIR))

from v3 import cast, hero, icons, monsters, portraits, ui, world  # noqa: E402
from v3.core import Canvas, fit, save  # noqa: E402

REPO_ROOT = ART_DIR.parents[1]


def _crop16(c: Canvas) -> Canvas:
    out = Canvas(16, 16)
    out.blit(c, (16 - c.w) // 2, (16 - c.h) // 2)
    return out


def build(root: Path) -> None:
    for who, opts in cast.CHARACTERS.items():
        save(hero.sheet(hero.Hero(opts)), root, f"assets/sprites/players/{who}.png")
    for eid, opts in cast.HUMANOIDS.items():
        save(hero.sheet(hero.Hero(opts)), root, f"assets/sprites/enemies/{eid}_sheet.png")
    for eid, draw in monsters.ENEMIES.items():
        save(monsters.sheet(draw()), root, f"assets/sprites/enemies/{eid}_sheet.png")
    for who, opts in {**cast.CHARACTERS, **cast.NPCS}.items():
        save(portraits.portrait(opts).image(2), root, f"assets/portraits/{who}.png")
    for name, *_ in icons.RELICS:
        save(icons.relic(name).image(), root, f"assets/sprites/icons/relics/{icons.snake(name)}.png")
    for school, glyph in icons.ABILITIES:
        save(icons.rune_stone(school, glyph).image(), root, f"assets/sprites/icons/abilities/{glyph}.png")
    for wid, _ in icons.WEAPONS:
        save(_crop16(icons.weapon(wid)).image(), root, f"assets/ui/icons/weapon_{wid}.png")
    for status in icons.STATUS:
        save(icons.status_icon(status).image(), root, f"assets/ui/icons/status_{status}.png")
    save(icons.pointer().image(), root, "assets/ui/icons/pointer.png")
    save(icons.potion_flask().image(), root, "assets/ui/icons/potion_flask.png")
    for kind in icons.PICKUPS:
        save(icons.pickup(kind).image(), root, f"assets/sprites/props/pickup_{kind}.png")
    for name, draw, size in (("chest", world.chest, (16, 14)), ("mining_node", world.mining_node, (16, 14)), ("breakable", world.breakable, (12, 14)),
                             ("lore_page", world.lore_page, (12, 10)), ("rope", world.rope, (14, 22)), ("shrine", world.shrine, (16, 22))):
        save(fit(draw(), *size).image(2), root, f"assets/sprites/props/{name}.png")
    for name, draw, size in (("crate_stack", world.crate, (16, 16)), ("lamp_post", world.lamp, (8, 20)), ("well", world.well, (16, 20))):
        save(fit(draw(), *size).image(2), root, f"assets/sprites/town/prop_{name}.png")
    for kind in world.BUILD:
        for lvl, state in enumerate(world.STATES):
            save(fit(world.building(kind, lvl), 64, 64, bottom=57).image(2), root, f"assets/sprites/town/{kind}_{state}.png")
    for biome in world.BIOMES:
        cell_h = 48 if biome == "collapsed_mines" else 32
        save(world.biome_atlas(biome, cell_h).image(2), root, f"assets/tilesets/{biome}/atlas.png")
    save(world.town_atlas().image(2), root, "assets/tilesets/town/atlas.png")
    for stage in range(4):
        save(world.pit_edge(stage).image(2), root, f"assets/tilesets/town/pit_edge_{stage}.png")
    for name, (canvas, _margin) in ui.FRAMES.items():
        save(canvas.image(), root, f"assets/ui/frames/{name}.png")


@lru_cache(maxsize=1)
def allowed_rgb() -> frozenset[tuple[int, int, int]]:
    colours: set[tuple[int, int, int]] = set()
    with tempfile.TemporaryDirectory() as tmp:
        build(Path(tmp))
        for png in Path(tmp).rglob("*.png"):
            with Image.open(png) as img:
                for _, (r, g, b, a) in img.convert("RGBA").getcolors(maxcolors=1 << 24) or []:
                    if a:
                        colours.add((r, g, b))
    return frozenset(colours)


if __name__ == "__main__":
    build(REPO_ROOT)
    print("gen_v3: wrote the v3 art set")
