"""v3 icons: 20 weapons, 38 rune stones, 88 relics, 8 status effects, UI pointer and
potion, and the 6 pickups. Each draws on an 18x18 canvas (16x16 art plus outline)."""

from __future__ import annotations

import re

from .core import Canvas, dk, lt, ramp

steel, steelD, wood, woodD, gold, rust, bone = "#c0ccd8", "#7a8898", "#9a6438", "#5a3820", "#f2c040", "#b0603a", "#efe3c4"


def _w(f) -> Canvas:
    s = Canvas(18, 18)
    f(s)
    return s.outline()


def _shortbow(s: Canvas) -> None:
    import math
    for a in range(0, 91, 3):
        r = math.pi * (180 + a) / 180
        s.px(14 + 11 * math.cos(r), 14 + 11 * math.sin(r), wood)
        s.px(14 + 10 * math.cos(r), 14 + 10 * math.sin(r), woodD)
    s.line(3, 14, 14, 3, "#e8e0d0"); s.line(6, 11, 13, 4, steelD); s.px(13, 4, steel)


WEAPONS: list[tuple[str, str]] = [
    ("pickaxe", "Pickaxe"), ("longsword", "Longsword"), ("twin_daggers", "Twin Daggers"), ("grave_scythe", "Grave Scythe"),
    ("sledgehammer", "Sledgehammer"), ("greataxe", "Greataxe"), ("rust_anchor", "Rust Anchor"), ("crossbow", "Crossbow"),
    ("shortbow", "Shortbow"), ("hand_cannon", "Hand Cannon"), ("throwing_knives", "Throwing Knives"), ("lantern_staff", "Lantern Staff"),
    ("spore_tome", "Spore Tome"), ("tide_orb", "Tide Orb"), ("blood_grimoire", "Blood Grimoire"), ("chain_whip", "Chain Whip"),
    ("drill_gauntlets", "Drill Gauntlets"), ("saw_boomerang", "Saw Boomerang"), ("reapers_chain", "Reaper's Chain"), ("leviathans_tooth", "Leviathan's Tooth"),
]


def _knives(s):
    for x0, y0, x1, y1 in ((4, 12, 9, 2), (8, 14, 14, 5), (2, 9, 4, 1)):
        s.line(x0, y0, x1, y1, steel); s.line(x0 - 1, y0 + 1, x0 + 1, y0 + 1, "#5a3a5a")
    s.line(4, 12, 9, 2, lt(steel, .5))


WEAPON_DRAW = {
    "pickaxe": lambda s: (s.line(3, 15, 11, 7, wood, 2), s.line(6, 3, 15, 12, steel, 2), s.line(6, 2, 14, 10, lt(steel, .5)), s.px(5, 4, steelD), s.px(15, 13, steelD)),
    "longsword": lambda s: (s.line(6, 11, 15, 2, steel, 2), s.line(6, 10, 14, 2, lt(steel, .6)), s.line(3, 9, 8, 14, gold), s.line(2, 15, 4, 13, woodD, 2), s.px(1, 16, gold)),
    "twin_daggers": lambda s: (s.line(4, 9, 10, 3, steel, 2), s.line(2, 11, 4, 9, "#5a3a5a", 2), s.line(2, 8, 5, 11, gold), s.line(13, 9, 7, 3, steel, 2), s.line(15, 11, 13, 9, "#5a3a5a", 2), s.line(15, 8, 12, 11, gold)),
    "grave_scythe": lambda s: (s.line(3, 16, 12, 3, woodD), s.line(4, 16, 13, 3, wood), s.line(12, 3, 7, 2, steel), s.line(12, 4, 6, 3, steel), s.line(7, 2, 3, 5, steel), s.line(6, 3, 3, 6, lt(steel, .5)), s.px(12, 2, "#7af0b0")),
    "sledgehammer": lambda s: (s.line(3, 15, 10, 8, wood, 2), s.line(8, 3, 15, 10, steelD, 4), s.line(8, 2, 14, 8, lt(steelD, .45))),
    "greataxe": lambda s: (s.ell(12, 6, 4, 4, steel), s.line(9, 2, 15, 8, lt(steel, .5)), s.line(2, 15, 12, 5, wood, 2), s.px(13, 4, steelD)),
    "rust_anchor": lambda s: (s.line(9, 3, 9, 14, rust, 2), s.ring(9.5, 2, 1.5, rust), s.line(6, 5, 13, 5, rust), s.line(3, 10, 9, 15, rust, 2), s.line(16, 10, 10, 15, rust, 2), s.px(3, 9, lt(rust, .3)), s.px(16, 9, lt(rust, .3))),
    "crossbow": lambda s: (s.line(3, 14, 12, 5, wood, 2), s.line(6, 3, 15, 12, steelD), s.line(7, 3, 15, 11, steelD), s.line(6, 4, 14, 12, "#e8e0d0"), s.line(10, 7, 15, 2, steel), s.px(15, 2, steel)),
    "shortbow": _shortbow,
    "hand_cannon": lambda s: (s.line(5, 11, 13, 4, "#4a4a5a", 4), s.line(5, 10, 12, 4, lt("#4a4a5a", .35)), s.line(12, 2, 16, 6, "#3a3a48", 2), s.line(4, 12, 2, 16, wood, 2), s.px(7, 9, gold)),
    "throwing_knives": _knives,
    "lantern_staff": lambda s: (s.line(3, 16, 10, 4, wood), s.line(10, 4, 13, 2, wood), s.rect(11, 5, 5, 7, steelD), s.rect(12, 6, 3, 5, "#ffe27a"), s.rect(13, 8, 1, 2, "#ff9a3a")),
    "spore_tome": lambda s: (s.rect(3, 3, 12, 13, "#4a7a3a"), s.rect(3, 3, 2, 13, gold), s.rect(14, 4, 1, 11, bone), s.ell(10, 8, 3, 2, "#c84a8a"), s.rect(9, 10, 2, 3, bone), s.px(9, 7, "#ffd0e0"), s.px(11, 8, "#ffd0e0")),
    "tide_orb": lambda s: (s.circ(9, 7, 5, "#3a8ad0"), s.ell(9, 9, 4, 1, "#7ad0f0"), s.px(7, 4, "#ffffff"), s.px(6, 5, "#d0f0ff"), s.rect(6, 13, 7, 2, gold), s.rect(5, 15, 9, 1, dk(gold, .3))),
    "blood_grimoire": lambda s: (s.rect(3, 3, 12, 13, "#6a1a2a"), s.rect(3, 3, 2, 13, "#2a1a1a"), s.rect(14, 4, 1, 11, bone), s.rows(7, 6, ["..#..", ".###.", "#####", "##+##", ".###."], {"#": "#e8304a", "+": "#ffa0a8"})),
    "chain_whip": lambda s: (s.line(2, 16, 5, 13, woodD, 2), [s.px(x, y, steelD) for x, y in ((6, 12), (8, 11), (9, 9), (10, 7), (12, 6), (13, 4))], [s.px(x, y, steel) for x, y in ((7, 12), (9, 10), (11, 7), (13, 5))], s.tri(14, 1, 16, 4, 13, 4, steel)),
    "drill_gauntlets": lambda s: (s.rect(2, 9, 7, 7, "#b0603a"), s.rect(3, 10, 5, 2, lt("#b0603a", .3)), s.tri(8, 8, 9, 14, 16, 3, steel), s.line(10, 9, 13, 6, steelD), s.line(9, 11, 14, 6, steelD), s.rect(2, 15, 7, 1, "#4a4a5a")),
    "saw_boomerang": lambda s: (s.line(3, 4, 9, 13, "#d0a040", 3), s.line(9, 13, 15, 4, "#d0a040", 3), [s.px(x, y, steel) for x, y in ((2, 6), (4, 9), (6, 12), (12, 12), (14, 9), (16, 6))]),
    "reapers_chain": lambda s: ([s.px(x, y, steel if i % 2 else steelD) for i, (x, y) in enumerate(((2, 15), (3, 13), (5, 12), (6, 10), (8, 9)))], s.line(9, 8, 10, 5, woodD, 2), s.line(10, 4, 16, 6, steel), s.line(10, 5, 15, 7, steel), s.line(16, 6, 16, 9, steel), s.px(10, 3, "#7af0b0")),
    "leviathans_tooth": lambda s: (s.tri(4, 13, 9, 15, 15, 1, bone), s.line(6, 13, 14, 2, lt(bone, .5)), s.line(2, 16, 6, 12, "#2a6a9a", 2), s.px(3, 14, "#7ad0f0")),
}


def weapon(wid: str) -> Canvas:
    return _w(WEAPON_DRAW[wid])


# ---- rune stones -----------------------------------------------------------------
GLYPH = {
    "meteor_call": ".......##|......##.|.....##..|..###+#..|.#####...|#++###...|#+####...|.####....|..##.....",
    "flame_dash": ".....#...|....##...|#...###..|....#+##.|##.##++#.|...#+++#.|#..#+++#.|....###..|.........",
    "inferno_ring": "..#.#.#..|.#######.|##.....##|#.......#|##.....##|#.......#|##.....##|.#######.|..#.#.#..",
    "glacier_spike": ".........|....#....|....#....|...+#..#.|.#.+#..#.|.#+##.+#.|+#+##.+##|+##+#++##|#########",
    "frozen_clone": "...###...|..#+++#..|..#+++#..|...###...|.#######.|#.#+++#.#|..#+++#..|..#...#..|.##...##.",
    "blizzard": "....#....|.#..#..#.|..#.#.#..|...###...|####+####|...###...|..#.#.#..|.#..#..#.|....#....",
    "chain_lightning": ".....###.|....###..|...###...|..######.|.....##..|....##...|...##....|..##.....|.#.......",
    "static_field": "..#...#..|.........|#..#.#..#|...+#+...|..##+##..|...+#+...|#..#.#..#|.........|..#...#..",
    "thunder_step": "....##...|...##....|..####...|....##...|...##....|.###.....|.#+##....|.#++####.|.#######.",
    "shadow_clones": "..#...#..|.###.###.|.###.###.|..#.#.#..|.#######.|...###...|..#####..|..#+++#..|..#...#..",
    "vanish": ".........|..#####..|.#.....#.|#..###..#|#.#+++#.#|#..###..#|.#.....#.|..#####..|.........",
    "umbral_grasp": ".#.#.#...|.#.#.#.#.|.#.#.#.#.|.#######.|.#######.|.######..|..#####..|..####...|..####...",
    "toxic_cloud": ".........|...###...|..#####..|.###+####|#####++##|#########|.#######.|.........|..#.#.#..",
    "plague_swarm": ".#.....#.|###...###|.#..#..#.|...###...|....#....|.#.....#.|###.#.###|.#.###.#.|....#....",
    "acid_rain": "..#####..|.#######.|#########|.........|.#..#..#.|.#..#..#.|...#..#..|#..#..#..|#.....#..",
    "boulder_roll": "..#####..|.#++####.|#++###.##|#+####.##|#####.###|####.####|#########|.#######.|..#####..",
    "stone_skin": ".#######.|#+++++++#|#+#####+#|#+#####+#|#+#####+#|.#+###+#.|.#+###+#.|..#+++#..|...###...",
    "fault_line": "....#....|....##...|...##....|...#.....|...###...|.....#...|....##...|...##....|...#.....",
    "blood_pact": "....#....|...###...|..#####..|..##+##..|.###+###.|.##+++##.|.#######.|..#####..|...###...",
    "crimson_leech": "#########|#+#####+#|.#+###+#.|.#+#.#+#.|..#+.+#..|..#+.+#..|...#.#...|...#.#...|.........",
    "hemoburst": "#...#...#|.#..#..#.|..#+#+#..|...+++...|####+####|...+++...|..#+#+#..|.#..#..#.|#...#...#",
    "black_hole": "..#####..|.#.....#.|#..###..#|#.#...#.#|#.#.#.#.#|#.#..##.#|#..#....#|.#..####.|..#......",
    "rift_walk": "...###...|..#+++#..|.#+...+#.|.#+...+#.|.#+...+#.|.#+...+#.|.#+...+#.|..#+++#..|...###...",
    "unmake": "#.......#|.#.....#.|..#.#.#..|...###...|...#+#...|...###...|..#.#.#..|.#.....#.|#.......#",
    "grapple_hook": ".....###.|....#..#.|....#....|....#....|....#....|.#..#..#.|.#..#..#.|..#.#.#..|...###...",
    "turret_drop": ".........|...###...|..#+++###|..#####..|...###...|..#####..|.#.#.#.#.|.#######.|.........",
    "mine_field": "....#....|.#..#..#.|..#####..|.##+++##.|###+#+###|.##+++##.|..#####..|.#.....#.|.........",
    "decoy_lantern": "...###...|....#....|..#####..|..#+++#..|..#+#+#..|..#+++#..|..#####..|...###...|.........",
    "smoke_bomb": ".....#.#.|......#..|...###...|..#+###..|.#+#####.|.#######.|.#######.|..#####..|...###...",
    "barrier_dome": ".........|...###...|..#+++#..|.#+...+#.|#+.....+#|#.......#|#.......#|#########|.........",
    "cave_in": ".##...##.|.##.#.##.|....#....|.##...##.|.##.#....|....#.##.|.##...##.|#########|#########",
    "foremans_fury": "..#.#.#..|.###.###.|.#+#+#+##|.#######.|.#++++##.|.######..|..#####..|..####...|..####...",
    "sunrise": "#...#...#|.#.....#.|...###...|..#+++#..|#.#+++#.#|..#+++#..|...###...|.#.....#.|#########",
    "thousand_cuts": "#......#.|.#....#..|..#..#...|...##....|...##..#.|..#..##..|.#...##..|#...#..#.|...#....#",
    "pits_embrace": "......##.|.....#+#.|.....#+#.|....#+#..|...#+#...|..#+#....|..#+#....|...#+#...|#########",
    "echo_storm": "..#####..|.#.....#.|#..###..#|#.#.+.#.#|#.#+#+#.#|#.#.+.#.#|#..###..#|.#.....#.|..#####..",
    "last_light": "....#....|...###...|...#+#...|####+####|#+++++++#|####+####|...#+#...|...#+#...|...###...",
    "spore_bloom": "..#####..|.#+#+#+#.|#+++++++#|#########|...###...|...#+#...|...#+#...|..#####..|.........",
}
SCHOOL = {"fire": "#f0702c", "frost": "#7ad4f4", "storm": "#f6d84a", "shadow": "#a07ae0", "poison": "#9ad040", "earth": "#c8965a",
          "blood": "#e8405a", "void": "#c060f0", "utility": "#e8e0cc", "ultimate": "#ffd25a"}
ABILITIES = [("fire", g) for g in ("meteor_call", "flame_dash", "inferno_ring")] + [("frost", g) for g in ("glacier_spike", "frozen_clone", "blizzard")] \
    + [("storm", g) for g in ("chain_lightning", "static_field", "thunder_step")] + [("shadow", g) for g in ("shadow_clones", "vanish", "umbral_grasp")] \
    + [("poison", g) for g in ("toxic_cloud", "plague_swarm", "acid_rain")] + [("earth", g) for g in ("boulder_roll", "stone_skin", "fault_line")] \
    + [("blood", g) for g in ("blood_pact", "crimson_leech", "hemoburst")] + [("void", g) for g in ("black_hole", "rift_walk", "unmake")] \
    + [("utility", g) for g in ("grapple_hook", "turret_drop", "mine_field", "decoy_lantern", "smoke_bomb", "barrier_dome")] \
    + [("ultimate", g) for g in ("cave_in", "foremans_fury", "sunrise", "thousand_cuts", "pits_embrace", "echo_storm", "last_light", "spore_bloom")]


def rune_stone(school: str, glyph: str, size: int = 18) -> Canvas:
    s, col, ult = Canvas(18, 18), SCHOOL[school], school == "ultimate"
    stone = "#4a3a5a" if ult else "#7a7266"
    s.circ(9, 9, 7, stone); s.ell(7, 6, 4, 3, lt(stone, .18)); s.ell(11, 12, 4, 3, dk(stone, .18)); s.circ(9, 9, 5, dk(stone, .32))
    if ult:
        s.ring(9, 9, 7, gold)
    s.rows(5, 5, GLYPH[glyph].split("|"), {"#": col, "+": lt(col, .6)})
    return s.outline()


# ---- status icons: element disc + glyph --------------------------------------------
STATUS = {"burn": ("fire", "flame_dash"), "chill": ("frost", "blizzard"), "freeze": ("frost", "glacier_spike"), "shock": ("storm", "chain_lightning"),
          "toxin": ("poison", "toxic_cloud"), "mark": ("shadow", "vanish"), "bleed": ("blood", "blood_pact"), "unravel": ("void", "black_hole")}


def status_icon(name: str) -> Canvas:
    school, glyph = STATUS[name]
    col = SCHOOL[school]
    s = Canvas(16, 16)
    s.circ(7.5, 7.5, 6.5, dk(col, .55)); s.circ(7.5, 7.5, 5.5, dk(col, .7))
    s.rows(3, 3, GLYPH[glyph].split("|"), {"#": col, "+": lt(col, .6)})
    return s.outline(polish=False)


# ---- relics --------------------------------------------------------------------------
SHAPES = {
    "boot": "ddddddd.....|.acaaab.....|.acaaab.....|.aaaaab.....|.aaaaab.....|.aaaaabbb...|.aaaaaaaabb.|.aaaaaaaaaab|.ddddddddde.",
    "mirror": "...ddddd....|..daaaaad...|.dacaaaaad..|.dacaaaaad..|.daaaaaaad..|.daaaaaaad..|..daaaaad...|...ddddd....|.....dd.....|.....ee.....|.....ee.....|.....dd.....",
    "cloth": "...aaaaa....|..aacccaa...|..acaaaab...|.aacaaaabb..|.aaaaaaabb..|.aaaaaaab.b.|aaaaaaaabbb.|aaaa.aaab.bb|aa.a.aa.b..b",
    "spring": "..dddddddd..|...aaaaaa...|..ab....ba..|...aaaaaa...|..ab....ba..|...aaaaaa...|..ab....ba..|...aaaaaa...|..dddddddd..",
    "blade": "..........ca|.........cab|........cab.|.......cab..|......cab...|.....cab....|..d.cab.....|..ddab......|...dd.......|..ee.dd.....|.ee...d.....|ee..........",
    "battery": "....d..d....|....d..d....|..dddddddd..|..aaaaaaab..|..acaaaaab..|..acaeaaab..|..aaeeeaab..|..aaaeaaab..|..aaaaaaab..|..bbbbbbbb..",
    "flask": "....dddd....|.....ee.....|.....ee.....|....eaae....|...eaaaae...|..eaaaaaae..|..ecaaaaab..|..ecaaaaab..|..eaaaaabb..|...eaaabb...|....eeee....",
    "arrow": "........ccc.|.........ca.|........c.a.|.......c....|......c.....|.....c......|..d.c.......|...d........|..d.d.......|.d..........",
    "orb": "....aaaa....|..aaaaaaaa..|.aaccaaaaab.|.acaaaaaaab.|aacaaaaaaabb|aaaaaaaaaabb|aaaaaaaaaabb|aaaaaaaaabbb|.aaaaaaabbb.|..abbbbbbb..|....bbbb....",
    "fang": ".dddddddddd.|.daaaaaaaad.|..aaaaaaaa..|..acaaaaab..|...caaaab...|...caaaab...|....aaab....|....aaab....|.....ab.....|.....ab.....",
    "rune": "...aaaaaa...|..aaaaaaab..|.aacaddaaab.|.acaadaaaab.|.acaaddaaab.|.aaaaaadaab.|.aaaaadaaab.|.aaaaddaaab.|.aaaaaaaabb.|..abbbbbbb..",
    "jar": "...dddddd...|....eeee....|...aaaaaa...|..acaaaaab..|.acaddaaaab.|.acaddaaaab.|.aaaaaaaaab.|.aaaaaaaabb.|..aaaaaabb..|...bbbbbb...",
    "flower": "....a..a....|...aca.aca..|..aaaadaaa..|...aaddda...|..aaaadaaa..|...aca.aa...|.....e......|...e.e......|....ee.ee...|.....eee....|.....e......",
    "die": ".aaaaaaaaa..|accaaaaaaab.|acdaaaadaab.|aaaaaaaaaab.|aaaaadaaaab.|aaaaaaaaaab.|aadaaaadaab.|aaaaaaaaaab.|abbbbbbbbbb.",
    "belt": "aaaadddddaaa|cccd.e.e.dcc|aaad.eee.daa|aaad.e.e.daa|bbbbdddddbbb",
    "armor": ".aa......aa.|aaaa....aaaa|aacaaaaaaaab|.acaaddaaab.|.acaaddaaab.|.aaaaddaaab.|.aaaaaaaaab.|..aaaaaaab..|..aaaaaaab..|..abbbbbbb..",
    "button": "....aaaa....|..aaccaaaa..|..acaaaaab..|..aaaaaaab..|.dddddddddd.|deeeeeeeeeed|deeeeeeeeeed|.dddddddddd.",
    "totem": "...dddddd...|..daaaaaad..|..daedaead..|..daaaaaad..|..dabbbbad..|...dddddd...|...daaaad...|...daeead...|...daaaad...|..dddddddd..",
    "shell": ".....aa.....|....acca....|...acaaab...|..acaabaab..|.acaabaabab.|.aaabaabaab.|aaababaababb|.aabaaabaab.|..bbbbbbbb..",
    "scroll": ".dddddddddd.|deaaaaaaaaed|.daccaaaaad.|.daaaaaaaad.|.daeeeeeead.|.daaaaaaaad.|.daeeeeaaad.|.daaaaaaaad.|deaaaaaaaaed|.dddddddddd.",
    "coin": "...dddddd...|..dccaaaad..|.dcaaaaaabd.|.dcaaeeaabd.|.daaeaaaabd.|.daaaeeaabd.|.daaaaaeabd.|.daaaeeaabd.|..dbbbbbbd..|...dddddd...",
    "eye": "...dddddd...|.ddaaaaaadd.|dacaaeeaaaad|dcaaeeeeaaad|daaaeceeaaad|.ddaaeeaadd.|...dddddd...",
    "lens": "..dddd......|.daaaad.....|daccaaad....|dacaaaad....|daaaaaad....|.daaaad.....|..ddddee....|......ee....|.......ee...|........ee..",
    "flame": ".....a......|....aa......|....aaa.a...|...aaaa.aa..|..aaadaaaa..|..aaddda.a..|.aaddcddaa..|.addcccdda..|.addccccda..|..adcccda...|...aaaaa....",
    "crystal": ".....a......|....aca.....|...acaab....|...acaab.a..|..acaaabab..|..acaaabab..|..acaaabbb..|..aaaaab.b..|..aaaaab....|...bbbbb....",
    "rod": ".....d......|....ddd.....|.....a......|....eae.....|.....a......|....eae.....|.....a......|.....a......|...ddddd....|..bbbbbbb...",
    "mask": "..aaaaaaaa..|.aaaaaaaaaa.|.acaaaaaaab.|.aeeaaaaeeb.|.aeeaaaaeeb.|.aaaaddaaab.|..aaaddaab..|...aaddab...|....adda....|.....dd.....",
    "book": ".dddddddddd.|deaaaaaaaab.|deaccaaaaab.|deacaddaaab.|deaaddddaab.|deaaaddaaab.|deaaaaaaaab.|deaaaaaaaab.|dddddddddd..|.cccccccc...",
    "brain": "..aaa.aaa...|.aacaaacaa..|acaabaaabaa.|acaaabaaaab.|aaabaaabaab.|.aaaabaaab..|..aaaaaabb..|....bbbb....|.....dd.....",
    "gear": "....a..a....|..aaaaaaaa..|..aaccaaab..|aaacabbcaabb|.aaab..baab.|.aaab..baab.|aaaacbbaaabb|..aaaaaabb..|..abbbbbbb..|....b..b....",
    "anchor": ".....dd.....|....d..d....|.....dd.....|...aaaaaa...|.....ab.....|.....ab.....|.a...ab...a.|.aa..ab..aa.|..aa.ab.aa..|...aaaaaa...|.....aa.....",
    "feather": ".........aa.|........aca.|.......acab.|......acaab.|.....acaab..|....acaab...|...acaab....|...aaab.....|..dbbb......|.d..........|d...........",
    "magnet": ".dddd..dddd.|.dddd..dddd.|.acab..acab.|.aaab..aaab.|.aaab..aaab.|.aaaaaaaaab.|..aaaaaaab..|...abbbbb...",
    "badge": ".....d......|....ddd.....|dddddadddd..|.ddaacaadd..|..daaaaad...|..daddaad...|.ddd...ddd..|.d.......d..",
    "crown": "d....d....d.|aa..aaa..aa.|aca.aca.aab.|acaaaaaaaab.|acaedaaedab.|aaaaaaaaaab.|bbbbbbbbbbb.",
    "heart": ".aaa...aaa..|accaa.aaaab.|acaaaaaaaab.|aaaaaaaaaab.|.aaaaaaaab..|..aaaaaab...|...aaaab....|....aab.....|.....b......",
    "hand": "..a.a.a.....|.aaaaaaa....|.acaaaaa.aa.|.acaaaaaaab.|.aaaaaaaab..|.aaaaaaab...|..aaaaab....|..ddddd.....|..ddddd.....",
    "clock": "...dddddd...|..daaaaaad..|.daaaeaaaad.|.daaaeaaaad.|.daaaeeeaad.|.daaaaaaaad.|.daaaaaaaad.|..daaaaaad..|...dddddd...|..ee....ee..",
    "ring": "....dd......|...dccd.....|....dd......|..aaaaaa....|.aca..aab...|.aa....ab...|.aa....ab...|.aab..abb...|..abbbbb....",
    "lantern": "....dddd....|....d..d....|...dddddd...|...daeead...|...daecad...|...daccad...|...daeead...|...dddddd...|....dddd....",
    "hammer": ".dddddddd...|.daaaaaad...|.dccaaaad...|.dddddddd...|....ee......|....ee......|....ee......|....ee......|....ee......|....dd......",
    "idol": "....aaa.....|...acaab....|...aeaeb....|...aaaab....|..aaaaaab...|.aaacaaaab..|.a.aaaab.b..|...aaaab....|..aa..aab...|.dddddddd...",
    "bell": ".....d......|....aaa.....|...acaab....|...acaab....|..acaaaab...|..acaaaab...|.aaaaaaaab..|dddddddddd..|.....ee.....",
    "bomb": ".......e.d..|......e.....|.....dd.....|...aaaaaa...|..acaaaaab..|.acaaaaaaab.|.aaaaaaaaab.|.aaaaaaaabb.|..aaaaabbb..|...abbbbb...",
    "horn": "..........dd|.........dad|.......aaaad|.....aaaacd.|...aaaaab...|..aaaabb....|.aaabb......|.abb........|dd..........",
    "hourglass": "dddddddddd|.aeeeeeea.|..aeeeea..|...aeea...|....aa....|...a.ca...|..a..eea..|.aeeeeeea.|dddddddddd",
    "hook": "....dd......|....dd......|....ee......|....ee......|..a.ee.a....|.aa.ee.aa...|.a..aa..a...|.aa.aa.aa...|..aaaaaa....",
    "skull": "..aaaaaa....|.aaaaaaaa...|acaaaaaaab..|aeeaaaeeab..|aeeaaaeeab..|aaaaeaaaab..|.aaaaaaab...|..aeaeaeb...|..aaaaab....",
    "golem": "..aaaaaaa...|.acaaaaaab..|.aaeeaeeab..|.aaddaddab..|.aaaaaaaab..|.aabbbbbab..|.aaaaaaaab..|..bbbbbbb...",
    "chain": ".aa.........|a..a........|a..aaa......|.aa..a......|...aa.aa....|.....a..a...|.....a..aaa.|......aa..a.|.........aa.",
}
TONE = {"Fire": "#e8642c", "Frost": "#8ad8f0", "Storm": "#f2d04a", "Poison": "#8ac83a", "Shadow": "#7a5ab0", "Blood": "#d0304a", "Void": "#a04ae0",
        "Gold": "#f2c040", "Bone": "#e8dcc0", "Steel": "#b8c4d0", "Stone": "#9a9488", "Wood": "#a8703a", "Teal": "#4ac0a0", "Blue": "#4a7ae0",
        "Glass": "#c8f0f0", "Cursed": "#8a2a5a", "Green": "#5ab04a", "White": "#f0ece0", "Dark": "#3a3448"}
RELICS = [
    ("Ember Boots", "boot", "Fire", "Wood"), ("Storm Sandals", "boot", "Storm", "Blue"), ("Mirror Step", "mirror", "Glass", "Gold"), ("Frostwalkers", "boot", "Frost", "White"),
    ("Ghost Wrap", "cloth", "White", "Glass"), ("Rebound Spring", "spring", "Steel", "Wood"), ("Echo Blade", "blade", "Steel", "Blue"), ("Spark Plug", "battery", "Storm", "Dark"),
    ("Hungry Steel", "blade", "Blood", "Dark"), ("Venom Gland", "flask", "Poison", "Dark"), ("Splitting Shot", "arrow", "Wood", "Steel"), ("Gravity Stone", "orb", "Dark", "Void"),
    ("Leech Fang", "fang", "Bone", "Blood"), ("Rune of Ricochet", "rune", "Stone", "Blue"), ("Volatile Core", "orb", "Fire", "Dark"), ("Soul Jar", "jar", "Glass", "Teal"),
    ("Bloodthirst", "fang", "Blood", "Dark"), ("Corpse Bloom", "flower", "Bone", "Green"), ("Domino", "die", "White", "Dark"), ("Trophy Belt", "belt", "Wood", "Gold"),
    ("Thorn Mail", "armor", "Steel", "Green"), ("Panic Button", "button", "Blood", "Steel"), ("Spite Totem", "totem", "Wood", "Blood"), ("Cracked Shell", "shell", "Bone", "Wood"),
    ("Revenge Pact", "scroll", "Bone", "Blood"), ("Lucky Coin", "coin", "Gold", "Wood"), ("Glass Cannonball", "orb", "Glass", "Steel"), ("Assassin's Mark", "eye", "Bone", "Shadow"),
    ("Jackpot", "coin", "Gold", "Blood"), ("Fracture Lens", "lens", "Glass", "Steel"), ("Kindling", "flame", "Fire", "Gold"), ("Permafrost", "crystal", "Frost", "White"),
    ("Lightning Rod", "rod", "Steel", "Storm"), ("Plague Doctor's Mask", "mask", "Bone", "Dark"), ("Shadow Ink", "flask", "Shadow", "Dark"), ("Void Shard", "crystal", "Void", "Dark"),
    ("Prism", "crystal", "Glass", "Gold"), ("Overcharger", "battery", "Blue", "Storm"), ("Spellweaver", "book", "Blue", "Gold"), ("Rune Battery", "battery", "Teal", "Gold"),
    ("Echo Rune", "rune", "Blue", "Glass"), ("Big Brain", "brain", "Blood", "Steel"), ("Momentum Gear", "gear", "Gold", "Steel"), ("Anchor Stone", "anchor", "Stone", "Wood"),
    ("Wall Runner", "boot", "Teal", "Stone"), ("Speed Demon", "feather", "Blood", "Dark"), ("Miner's Luck", "coin", "Gold", "Stone"), ("Ore Magnet", "magnet", "Blood", "Steel"),
    ("Treasure Map", "scroll", "Bone", "Blood"), ("Merchant's Badge", "badge", "Gold", "Wood"), ("Echo Collector", "jar", "Glass", "Void"), ("Crown of the Deep", "crown", "Teal", "Gold"),
    ("Second Wind", "feather", "White", "Gold"), ("Hydra Heart", "heart", "Green", "Gold"), ("Titan's Grip", "hand", "Stone", "Gold"), ("Clockwork Heart", "clock", "Gold", "Steel"),
    ("Infinity Loop", "ring", "Void", "Glass"), ("Mimic Crown", "crown", "Wood", "Blood"), ("The Pit's Eye", "eye", "Dark", "Void"), ("Necro Lantern", "lantern", "Dark", "Teal"),
    ("Worldbreaker", "hammer", "Stone", "Fire"), ("Golden Idol", "idol", "Gold", "Dark"), ("Twin Souls", "heart", "Glass", "Shadow"), ("Chaos Engine", "gear", "Void", "Fire"),
    ("Rot Lung", "flask", "Green", "Bone"), ("Acid Flask", "flask", "Poison", "Glass"), ("Frost Fang", "fang", "Frost", "Blue"), ("Thunder Bell", "bell", "Storm", "Wood"),
    ("Night Cowl", "cloth", "Shadow", "Dark"), ("Ember Heart", "heart", "Fire", "Gold"), ("Bomb Bag", "bomb", "Dark", "Fire"), ("Portal Stone", "rune", "Void", "Glass"),
    ("Healing Totem", "totem", "Green", "White"), ("War Horn", "horn", "Bone", "Gold"), ("Pocket Golem", "golem", "Stone", "Teal"), ("Gambler's Die", "die", "Blood", "White"),
    ("Time Hourglass", "hourglass", "Glass", "Gold"), ("Grappling Claw", "hook", "Steel", "Wood"), ("Lantern of Souls", "lantern", "Dark", "Glass"), ("Mega Magnet", "magnet", "Blue", "Steel"),
    ("Cursed Crown", "crown", "Cursed", "Void"), ("Bleeding Heart", "heart", "Blood", "Dark"), ("Coward's Cloak", "cloth", "Cursed", "Dark"), ("Hunger Ring", "ring", "Cursed", "Blood"),
    ("Glass Body", "skull", "Glass", "Cursed"), ("Pit Pact", "scroll", "Dark", "Cursed"), ("Greed Chain", "chain", "Gold", "Cursed"), ("Silence Stone", "rune", "Dark", "Stone"),
]


def snake(name: str) -> str:
    return re.sub(r"[^a-z0-9]+", "_", name.lower().replace("'", "")).strip("_")


def shape_icon(shape: str, base: str, acc: str, size: int = 16) -> Canvas:
    rows = SHAPES[shape].split("|")
    a, d = TONE.get(base, base), TONE.get(acc, acc)
    s = Canvas(size, size)
    w, h = max(len(r) for r in rows), len(rows)
    s.rows((size - w) // 2, (size - h) // 2, rows, {"a": a, "b": dk(a, .35), "c": lt(a, .5), "d": d, "e": dk(d, .3)})
    return s.outline()


def relic(name: str) -> Canvas:
    _, shape, base, acc = next(r for r in RELICS if r[0] == name)
    return shape_icon(shape, base, acc)


PICKUPS = {"gold": ("coin", "Gold", "Wood"), "ore": ("crystal", "#d8803a", "Dark"), "echo": ("crystal", "#9a6af0", "Glass"),
           "potion": ("flask", "#e8405a", "Wood"), "relic": ("orb", "Gold", "Dark"), "rune": ("rune", "Stone", "Blue")}


def pickup(kind: str) -> Canvas:
    shape, a, d = PICKUPS[kind]
    big = shape_icon(shape, a, d, 16)
    # 14x14 target: trim one pixel border
    out = Canvas(14, 14)
    out.blit(big, -1, -1)
    return out


def pointer() -> Canvas:
    s = Canvas(16, 16)
    s.rows(2, 1, ["#.........", "##........", "#+#.......", "#++#......", "#+++#.....", "#++++#....", "#+++++#...", "#++++++#..",
                  "#+++####..", "#++#......", "#+#.......", "##........"], {"#": "#3b1d0c", "+": "#f8e4b8"})
    return s


def potion_flask() -> Canvas:
    return shape_icon("flask", "#e8405a", "Wood", 16)
