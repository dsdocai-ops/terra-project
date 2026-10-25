"""Master palette for every generated asset (specs/SPEC-art-audio.md, "Master palette").

Generators import colors from here by name. A literal RGB in a sprite script
is a review failure. All values are uppercase "#RRGGBB" strings; use rgb() or
rgb_set() to get tuples for Pillow. pixel.Canvas resolves names through ALL.

Global set: 8 hue ramps x 5 steps (shadow, dark, base, light, highlight),
1 neutral ramp of 7 grays (neutral_0 darkest), and 2 pure accents. Ramps are
hue-shifted: shadows lean cool, highlights lean warm.

Each biome palette is a named 24-color selection from the global set plus up
to 8 biome-only colors. The biome-only colors are the five from the spec
table (ground base, wall base, accent 1, accent 2, light); the 3 free slots
are for the biome's first real tileset pass. Biome-only colors are addressed
as "<biome_id>.<name>" ("collapsed_mines.lantern") from any generator, and
by their bare name ("lantern") on a Canvas built from that biome's colors.

Materials (MATERIAL) are 4-step light-to-dark ramps of global color names for
the things characters, props and icons are made of (cloth, iron, timber, ...).
Every biome also carries a ground and a wall ramp built around its two spec
table bases.

Changelog (a palette locks once the biome's first real tileset is approved;
edits after that are a human decision recorded here):
- 2026-10-19: created. Spec table colors (biome, UI, rarity, element, accents)
  copied from SPEC-art-audio and locked. Global ramps and biome selections are
  drafts until each biome's first tileset review.
- 2026-10-21: MATERIAL ramps, per-biome ground/wall ramps and the qualified
  "<biome>.<name>" addressing added so Dev B's generators draw from this
  module alone (merge of feat/ui-hud-pixel-art-pass). drowned_city swaps
  neutral_5 for neutral_0 and the_heart swaps neutral_3 for neutral_0 so each
  wall ramp has a darkest step; both selections are still drafts.
- 2026-10-24: art direction v2 (decision D5, Dev A and Dev B). Adds the v2
  layer below the v1 tables: V2_RAMPS (named ramps from the approved mockups,
  docs/art-direction/v2/), CHARACTER_SLOTS / V2_CHARACTERS (the BODY template
  palettes), and V2_SETS (which ramps a UI, collapsed_mines or town v2 canvas
  may use). v1 tables are unchanged so committed v1 assets still pass
  build_all.py --check; each v1 table retires when its assets are regenerated
  in v2 (AR-3 mines tiles, AR-5 town, AR-12 theme). Remaining biomes get their
  v2 ramps in AR-6.
"""

from __future__ import annotations

from collections.abc import Iterable, Mapping
from dataclasses import dataclass, field
from types import MappingProxyType

RAMP_STEPS: tuple[str, ...] = ("shadow", "dark", "base", "light", "highlight")

# 8 hue ramps, steps in RAMP_STEPS order.
RAMPS: Mapping[str, tuple[str, ...]] = MappingProxyType({
    "red":    ("#4A1426", "#7A1F2E", "#B8323A", "#E05A4E", "#F79A7A"),
    "orange": ("#5A2414", "#8E3E1A", "#C86428", "#EE9440", "#FFC878"),
    "yellow": ("#5E4418", "#957022", "#CFA530", "#EED15A", "#FFF0A0"),
    "green":  ("#14382A", "#23583A", "#3C8A44", "#6CBA52", "#B0E07A"),
    "teal":   ("#0E2E36", "#174A50", "#24746E", "#3AA894", "#7EDCC0"),
    "blue":   ("#141E46", "#22366E", "#3460A8", "#5294D8", "#94CCF4"),
    "violet": ("#26143E", "#40206A", "#64379E", "#9060CC", "#C49CEE"),
    "brown":  ("#2A1A16", "#45291E", "#6A432C", "#94673E", "#C09868"),
})

# 7 grays, darkest first, very slightly cool to sit next to the outline color.
NEUTRAL: tuple[str, ...] = ("#262428", "#3C3A40", "#57545C", "#77737C", "#9A979E", "#C2C0C4", "#E6E5E8")

ACCENT: Mapping[str, str] = MappingProxyType({
    "hit_flash": "#FFFFFF",
    "outline": "#1A1420",
})


def _build_global() -> Mapping[str, str]:
    colors: dict[str, str] = {}
    for ramp, steps in RAMPS.items():
        for step, value in zip(RAMP_STEPS, steps, strict=True):
            colors[f"{ramp}_{step}"] = value
    for i, value in enumerate(NEUTRAL):
        colors[f"neutral_{i}"] = value
    colors.update(ACCENT)
    return MappingProxyType(colors)


# Every global color by name: "<ramp>_<step>", "neutral_<0..6>", "hit_flash", "outline".
GLOBAL: Mapping[str, str] = _build_global()


def _ramp(name: str, *steps: str) -> tuple[str, ...]:
    """Selection helper: _ramp("brown") is all 5 steps, _ramp("red", "dark") one."""
    return tuple(f"{name}_{s}" for s in (steps or RAMP_STEPS))


def _neutral(*indices: int) -> tuple[str, ...]:
    return tuple(f"neutral_{i}" for i in indices)


_ALWAYS: tuple[str, ...] = ("outline", "hit_flash")


def ramp4(hue: str, high: bool = False) -> tuple[str, str, str, str]:
    """Four consecutive steps of a hue ramp as names, light to dark.
    ramp4("red") is (light, base, dark, shadow); high=True shifts up one step
    to (highlight, light, base, dark). Shading code indexes 0 = most lit."""
    if hue not in RAMPS:
        raise KeyError(hue)
    steps = ("highlight", "light", "base", "dark") if high else ("light", "base", "dark", "shadow")
    return tuple(f"{hue}_{s}" for s in steps)  # type: ignore[return-value]


def grays(*indices: int) -> tuple[str, ...]:
    """Neutral steps as names, in the order given (write them light to dark)."""
    return _neutral(*indices)


# Material ramps, light -> dark, 4 global names each. Characters, props and
# icons are drawn from these; tiles use the biome ground and wall ramps.
MATERIAL: Mapping[str, tuple[str, str, str, str]] = MappingProxyType({
    "rock":   ramp4("brown"),
    "wall":   ("brown_base", "brown_dark", "brown_shadow", "neutral_0"),
    "timber": ("orange_light", "brown_light", "brown_base", "brown_dark"),
    "iron":   ("neutral_5", "neutral_4", "neutral_2", "neutral_1"),
    "copper": ramp4("orange"),
    "gold":   ramp4("yellow", high=True),
    "cloth":  ("orange_base", "orange_dark", "brown_base", "brown_dark"),
    "skin":   ("orange_highlight", "brown_highlight", "brown_light", "brown_base"),
    "hat":    ("yellow_light", "yellow_base", "yellow_dark", "yellow_shadow"),
    "echo":   ramp4("violet", high=True),
    "relic":  ramp4("blue", high=True),
    "ore":    ramp4("orange", high=True),
    "blood":  ramp4("red"),
    "bone":   ("neutral_6", "neutral_5", "neutral_4", "neutral_3"),
    "ash":    ("neutral_4", "neutral_3", "neutral_2", "neutral_1"),
    "slate":  ("neutral_3", "neutral_2", "neutral_1", "neutral_0"),
})


@dataclass(frozen=True)
class BiomePalette:
    """One biome's colors. ground, wall, accent_1, accent_2, light are the spec
    table values; colors maps every name usable in this biome to its hex.
    ground_ramp and wall_ramp are 4 names light -> dark around the two bases,
    written with the qualified "<id>.ground" / "<id>.wall" names so they work
    on any Canvas."""

    id: str
    mood: str
    ground: str
    wall: str
    accent_1_name: str
    accent_1: str
    accent_2_name: str
    accent_2: str
    light_name: str
    light: str
    selection: tuple[str, ...]
    ground_ramp: tuple[str, str, str, str]
    wall_ramp: tuple[str, str, str, str]
    extra: Mapping[str, str] = field(default_factory=dict)

    @property
    def biome_only(self) -> dict[str, str]:
        """Colors not in the global set, by bare name. Accents and light are
        keyed by their spec names (copper, lantern, warm, ...)."""
        return {
            "ground": self.ground,
            "wall": self.wall,
            self.accent_1_name: self.accent_1,
            self.accent_2_name: self.accent_2,
            self.light_name: self.light,
            **self.extra,
        }

    def qualified(self, name: str) -> str:
        """"<id>.<name>": how a biome-only color is addressed from any Canvas."""
        if name not in self.biome_only:
            raise KeyError(f"{name!r} is not a {self.id} color")
        return f"{self.id}.{name}"

    @property
    def accent_1_ref(self) -> str:
        return self.qualified(self.accent_1_name)

    @property
    def accent_2_ref(self) -> str:
        return self.qualified(self.accent_2_name)

    @property
    def light_ref(self) -> str:
        return self.qualified(self.light_name)

    @property
    def colors(self) -> dict[str, str]:
        """Selection plus biome-only colors by bare name (24 + 5..8 entries)."""
        return {**{name: GLOBAL[name] for name in self.selection}, **self.biome_only}

    @property
    def names(self) -> dict[str, str]:
        """Every name a Canvas for this biome resolves: the selection, the
        biome-only colors by bare name and by qualified name."""
        return {**self.colors, **{self.qualified(k): v for k, v in self.biome_only.items()}}

    def rgb(self) -> frozenset[tuple[int, int, int]]:
        """Allowed colors for build_all.py's palette check."""
        return frozenset(rgb_set(self.colors.values()))


_BIOMES: tuple[BiomePalette, ...] = (
    BiomePalette(
        id="collapsed_mines",
        mood="warm brown rock, copper, lantern orange",
        ground="#6B4A32", wall="#4A3626",
        accent_1_name="copper", accent_1="#C8783A",
        accent_2_name="lantern", accent_2="#FFB347",
        light_name="warm", light="#FFD9A0",
        selection=_ALWAYS
        + _ramp("brown") + _ramp("orange")
        + _ramp("yellow", "dark", "base", "light", "highlight")
        + _ramp("red", "shadow", "dark", "base")
        + _neutral(0, 1, 2, 3, 4),
        ground_ramp=("brown_light", "collapsed_mines.ground", "brown_dark", "brown_shadow"),
        wall_ramp=("brown_base", "collapsed_mines.wall", "brown_shadow", "neutral_0"),
    ),
    BiomePalette(
        id="fungal_caverns",
        mood="dark teal, violet spores, bioluminescent cyan",
        ground="#2E4A48", wall="#1F3230",
        accent_1_name="spore_violet", accent_1="#9B5DE5",
        accent_2_name="glow_cyan", accent_2="#5EF2E0",
        light_name="cool", light="#A8FFF4",
        selection=_ALWAYS
        + _ramp("teal") + _ramp("violet")
        + _ramp("blue", "shadow", "dark", "base", "light")
        + _ramp("green", "shadow", "dark", "base", "light")
        + _neutral(0, 1, 2, 3),
        ground_ramp=("teal_base", "fungal_caverns.ground", "teal_dark", "teal_shadow"),
        wall_ramp=("teal_dark", "fungal_caverns.wall", "teal_shadow", "neutral_0"),
    ),
    BiomePalette(
        id="crystal_hollows",
        mood="cold blue-gray, pink and cyan crystal facets",
        ground="#4A5A78", wall="#2F3A52",
        accent_1_name="crystal_pink", accent_1="#F28CC9",
        accent_2_name="crystal_cyan", accent_2="#8CE8FF",
        light_name="white_blue", light="#E8F6FF",
        selection=_ALWAYS
        + _ramp("blue") + _ramp("violet")
        + _ramp("teal", "dark", "base", "light", "highlight")
        + _ramp("red", "highlight")
        + _neutral(0, 1, 2, 3, 4, 5, 6),
        ground_ramp=("neutral_4", "crystal_hollows.ground", "blue_dark", "blue_shadow"),
        wall_ramp=("blue_dark", "crystal_hollows.wall", "blue_shadow", "neutral_0"),
    ),
    BiomePalette(
        id="drowned_city",
        mood="deep green-blue stone, algae, pearl",
        ground="#2C4A5E", wall="#1C3240",
        accent_1_name="algae", accent_1="#5FA36A",
        accent_2_name="pearl", accent_2="#E6E1D3",
        light_name="murky", light="#6FA8C9",
        selection=_ALWAYS
        + _ramp("teal") + _ramp("blue") + _ramp("green")
        + _ramp("yellow", "light", "highlight")
        + _neutral(0, 1, 2, 3, 4),
        ground_ramp=("teal_base", "drowned_city.ground", "blue_dark", "blue_shadow"),
        wall_ramp=("blue_dark", "drowned_city.wall", "blue_shadow", "neutral_0"),
    ),
    BiomePalette(
        id="ember_forge",
        mood="black iron, lava orange, steam gray",
        ground="#3A2E2E", wall="#241C1C",
        accent_1_name="lava", accent_1="#FF6A1F",
        accent_2_name="hot_yellow", accent_2="#FFD23F",
        light_name="furnace", light="#FF9A4A",
        selection=_ALWAYS
        + _ramp("red") + _ramp("orange") + _ramp("yellow")
        + _neutral(0, 1, 2, 3, 4, 5, 6),
        ground_ramp=("neutral_2", "ember_forge.ground", "neutral_1", "neutral_0"),
        wall_ramp=("neutral_3", "ember_forge.wall", "neutral_1", "neutral_0"),
    ),
    BiomePalette(
        id="the_heart",
        mood="flesh red, vein purple, bone",
        ground="#5A2A3A", wall="#3A1A28",
        accent_1_name="vein_purple", accent_1="#8A2BE2",
        accent_2_name="bone", accent_2="#E8DCC8",
        light_name="pulse", light="#FF3C6E",
        selection=_ALWAYS
        + _ramp("red") + _ramp("violet")
        + _ramp("brown", "shadow", "dark", "base", "light")
        + _ramp("orange", "light", "highlight")
        + _ramp("yellow", "light", "highlight")
        + _neutral(0, 4, 5, 6),
        ground_ramp=("red_dark", "the_heart.ground", "red_shadow", "violet_shadow"),
        wall_ramp=("red_shadow", "the_heart.wall", "violet_shadow", "neutral_0"),
    ),
    BiomePalette(
        id="town",
        mood="daylight, timber, thatch, sky",
        ground="#7A9A4E", wall="#8A6A42",
        accent_1_name="thatch", accent_1="#D9B04C",
        accent_2_name="sky", accent_2="#8FD3FF",
        light_name="day", light="#FFF4D6",
        selection=_ALWAYS
        + _ramp("green") + _ramp("brown") + _ramp("yellow")
        + _ramp("blue", "dark", "base", "light", "highlight")
        + _neutral(2, 4, 6),
        ground_ramp=("green_light", "town.ground", "green_base", "green_dark"),
        wall_ramp=("brown_highlight", "town.wall", "brown_base", "brown_dark"),
    ),
)

BIOMES: Mapping[str, BiomePalette] = MappingProxyType({b.id: b for b in _BIOMES})
BIOME_IDS: tuple[str, ...] = tuple(BIOMES)

UI: Mapping[str, str] = MappingProxyType({
    "parchment": "#E8D8B0",
    "ink": "#2B2118",
    "frame_bronze": "#9A6A2E",
    "hp_red": "#D83A3A",
    "teammate_green": "#5FBF6A",
    "mana_blue": "#4A8AE8",
    "gold": "#F2C14E",
})

RARITY: Mapping[str, str] = MappingProxyType({
    "common": "#CFCFCF",
    "uncommon": "#5FBF6A",
    "rare": "#4A8AE8",
    "epic": "#9B5DE5",
    "legendary": "#F2A33A",
    "cursed": "#B02E5A",
})

# Shared by icons, VFX, status pips, and damage numbers.
ELEMENT: Mapping[str, str] = MappingProxyType({
    "fire": "#FF7A2F",
    "frost": "#7FD6FF",
    "storm": "#F7E86B",
    "shadow": "#6E4A9E",
    "poison": "#7FDF4A",
    "earth": "#B08A4A",
    "blood": "#C8203A",
    "void": "#3A1F6E",
    "utility": "#C8C8C8",
})


# --- v2 layer (art direction v2, decision D5, 2026-10-24) ------------------------
#
# Named ramps taken from the approved mockups (docs/art-direction/v2/). Each
# color is addressed as "<ramp>_<n>", n = 0 the lightest step, so a ramp reads
# light -> dark like MATERIAL. Two ramps are not lightness-ordered and say so:
# rarity_v2 (common, rare, epic, legendary, cursed) and flowers. A hex may
# repeat across ramps (the mockups reuse colors), never within one.
# docs/art-direction/v2/palette-map.md records how every mockup color maps here.

V2_RAMPS: Mapping[str, tuple[str, ...]] = MappingProxyType({
    # UI
    "void":       ("#8A93AE", "#6B7590", "#474F68", "#2E3449", "#1E2233", "#12141F", "#0C0E16", "#07080D"),
    "lamp":       ("#FFF3C4", "#F7D27A", "#E0A040", "#A8661E", "#6A3A12", "#3A1E0C"),
    "bone":       ("#EDE4D3", "#E8C9A0", "#C9BBA0", "#9A8F7E", "#5A4630"),
    "ash":        ("#B5AEC0", "#9A93A6", "#6E6880"),
    "wood":       ("#94643A", "#6E4428", "#4A2C1A", "#2A1810", "#1E1009"),
    "parchment":  ("#EFE2BC", "#EAD8AE", "#DCC69A", "#D8C49A", "#C8B080", "#A88E64", "#7A6444"),
    "ink":        ("#9A2A1A", "#6A5034", "#3A2414"),
    "blood":      ("#FFB0A0", "#F0605A", "#C8323A", "#7A1A22", "#3A0E14"),
    "hp":         ("#FFE0B0", "#FFD0C0", "#FF7A6A", "#FF4A4A", "#E0303A", "#9A1A22", "#7A1018"),
    "rage":       ("#FFD15C", "#FF8A1E", "#3A1A06"),
    "echo":       ("#E6DCFF", "#C9B6FF", "#9C7CFF", "#8E6CF0", "#6B4FC0", "#5B3FC4", "#4A2E9A", "#1E1240"),
    "glow":       ("#FFF6D0", "#FFE6A8", "#FFD27A", "#FFC86A"),
    "party_teal": ("#A8F0E4", "#3FC1B8", "#1E6A66", "#0E2E30"),
    "party_rose": ("#FFC0DA", "#E879A6", "#A83A72", "#4A1430"),
    "party_lime": ("#E0FFA0", "#A6D65A", "#4A7A28", "#1E3014"),
    "rim_storm":  ("#9FE6FF", "#2A5AA8", "#102040"),
    "rim_fire":   ("#FFD15C", "#D8601E", "#7A2410"),
    "rim_frost":  ("#E0F8FF", "#3FA0D0", "#1A4A6A"),
    "rim_steel":  ("#EDE4D3", "#8A93AE", "#474F68"),
    "rim_brass":  ("#FFF3C4", "#E0A040", "#A8661E"),
    "rim_rare":   ("#BFE0FF", "#2A5AA8", "#102040"),
    "rim_epic":   ("#C9B6FF", "#4A2E9A", "#1E1240"),
    "rarity_v2":  ("#B9B2A5", "#4FA3FF", "#A77BFF", "#F2B65A", "#D9385E"),
    "tab":        ("#FF8A4A", "#C8501E", "#5A1408"),
    "ult":        ("#FFB040", "#E07A1E"),
    "sunset":     ("#FFD89A", "#F7B878", "#F09A68", "#E07A5A", "#C85A4E", "#8A4A3A"),
    # Collapsed Mines
    "mine_floor":       ("#B08058", "#A0704A", "#80553A", "#7A4E32", "#744A2E", "#6A4430", "#4A2E1C", "#3A2214"),
    "mine_stone":       ("#A08A74", "#86705C", "#7A6450", "#7A6250", "#6E5646", "#5E4A3C", "#5A4638", "#3A2A20"),
    "mine_stone_shade": ("#736354", "#605142", "#58483A", "#58473A", "#4F3E32", "#44352B", "#413228", "#2A1E17"),
    "timber":           ("#B07A44", "#9A6A3A", "#7A4A26", "#6A3E1E", "#5A3420", "#4A2A18", "#3A2214", "#2A1810"),
    "copper":           ("#FFC28A", "#E0956A", "#C9733A", "#A16B4C", "#7A3E1E", "#5A2A14"),
    "iron_v2":          ("#B8C0CC", "#9AA0AE", "#8A8F9A", "#7A808E", "#5A5F6A", "#4E5462", "#4A4E5A", "#3A3E4A", "#2A2E38", "#1A1A20"),
    "crate":            ("#E8C080", "#D0A064", "#C88A50", "#A86E3C", "#8A5A30", "#6A3E20"),
    "rubble":           ("#A08A70", "#6E5A48", "#2A1A10"),
    "gas":              ("#C8FFA0", "#9AE070", "#7BE05A"),
    "danger":           ("#FF4A3A",),
    # Town
    "grass":      ("#9AD060", "#86C04E", "#78B84A", "#64A43E", "#5E9E3A", "#589636", "#3E7428", "#2E6A22", "#20401A"),
    "leaf":       ("#A8D870", "#86C04E", "#5A9A3A", "#3E7A2E", "#2E5A22", "#20401A"),
    "fruit":      ("#FF9A80", "#E04A3A"),
    "flowers":    ("#F7F0E0", "#FFD15C", "#E879A6", "#8AB8FF", "#E04A3A"),
    "cobble":     ("#E2D4B4", "#CDBC9C", "#C4B090", "#B8A484", "#8E7E66", "#6A5C48"),
    "dirt":       ("#D0A070", "#B8885A", "#B08254", "#8A6440"),
    "plaster":    ("#E2D2B0", "#C4B290", "#BBA884", "#9A8866"),
    "plank":      ("#E8C090", "#E0B070", "#C8945A", "#C8884E", "#A86E3C", "#9A6236", "#7E4E28", "#6A3E20", "#3A2214"),
    "roof_red":   ("#E07A58", "#D8664A", "#D8502E", "#B8442E", "#B03A22", "#8E3020", "#8A2A18", "#7A2818", "#5A1A10"),
    "roof_teal":  ("#6EAABA", "#3E8AA8", "#3E7A8A", "#2E6A88", "#2E5A6A", "#24485A", "#1E4A68", "#1A3440"),
    "foundation": ("#B8B2A6", "#A8A294", "#9A9488", "#8E887C", "#8A8478", "#7A7468", "#77716A", "#6A6458", "#5A5448"),
    "window":     ("#F2E6CC", "#E0D2B4", "#9AC4E6", "#3E5E84", "#2E6A3A"),
    "water":      ("#3A5A7A", "#2A4060"),
    "lamp_iron":  ("#4A3A2E", "#3A3A44", "#3A2A20", "#2A2A30"),
    "night":      ("#6A9A4E", "#54803E", "#4E7A3A", "#487236", "#2E5226"),
})

# The BODY template (players, NPCs, humanoid enemies): one string-row sprite,
# recolored per character. CHARACTER_SLOTS is the slot order; the template's
# row characters are o Y y L H S s e J j B G N n K in this order.
CHARACTER_SLOTS: tuple[str, ...] = (
    "outline", "helmet", "helmet_shade", "lamp", "hair", "skin", "skin_shade", "eye",
    "jacket", "jacket_shade", "strap", "glove", "pants", "pants_shade", "boot",
)
CHARACTER_CHARS: str = "oYyLHSseJjBGNnK"

_WREN: tuple[str, ...] = ("#3A2014", "#F2B65A", "#C7782E", "#FFF6D0", "#7A4422", "#EDB98E", "#D0946A", "#2A1A14",
                          "#D9572B", "#A83A1E", "#6A3A1E", "#8A5A30", "#3E4E74", "#2C3858", "#5A3420")


def _char(**over: str) -> tuple[str, ...]:
    slots = dict(zip(CHARACTER_SLOTS, _WREN, strict=True))
    for key, value in over.items():
        if key not in slots:
            raise KeyError(key)
        slots[key] = value
    return tuple(slots[s] for s in CHARACTER_SLOTS)


V2_CHARACTERS: Mapping[str, tuple[str, ...]] = MappingProxyType({
    "wren": _WREN,
    "kestrel": _char(helmet="#4A5A6E", helmet_shade="#2E3A4A", lamp="#E0FFF8", hair="#2A2A30", skin="#E2B48A", skin_shade="#C0906A",
                     jacket="#2E9E96", jacket_shade="#1E6A66", strap="#164A46", glove="#3A3040", pants="#3A3040", pants_shade="#2A2230"),
    "ivy": _char(helmet="#7A3A6A", helmet_shade="#4E2244", lamp="#FFD0F0", hair="#E8C060", skin="#C08860", skin_shade="#9A6844",
                 jacket="#C85A94", jacket_shade="#8A2E62", strap="#5A1E44", pants="#2A2238", pants_shade="#1E1828"),
    "brann": _char(helmet="#8A8F9A", helmet_shade="#5A5F6A", hair="#B8B8B8", skin="#C08A60", skin_shade="#9A6A44",
                   jacket="#6E9A3E", jacket_shade="#4A6A28", strap="#3A5420", pants="#3A2A1A", pants_shade="#2A1E12"),
    "hilde": _char(outline="#2A1410", helmet="#8A8FA0", helmet_shade="#5E6372", lamp="#FFE07A", hair="#C8CCD8", skin="#8E5C3C", skin_shade="#6E4228",
                   jacket="#C2622E", jacket_shade="#8A3A1A", strap="#EFE2C8", glove="#5A3A2A", pants="#6A4258", pants_shade="#4A2A3E", boot="#3A2418"),
    "hollow_miner": _char(outline="#1A1420", helmet="#6E7086", helmet_shade="#4A4C5E", lamp="#2A2A34", hair="#3A3A44", skin="#9AB08E", skin_shade="#76907A",
                          eye="#D8C8FF", jacket="#5A4E70", jacket_shade="#3E3452", strap="#2D2640", glove="#76907A", pants="#3A3A48",
                          pants_shade="#2A2A36", boot="#2A2230"),
})


def _build_v2() -> Mapping[str, str]:
    colors: dict[str, str] = {}
    for ramp, steps in V2_RAMPS.items():
        if len(set(steps)) != len(steps):
            raise ValueError(f"v2 ramp {ramp} repeats a color")
        for i, value in enumerate(steps):
            colors[f"{ramp}_{i}"] = value
    for who, values in V2_CHARACTERS.items():
        for slot, value in zip(CHARACTER_SLOTS, values, strict=True):
            colors[f"char_{who}_{slot}"] = value
    return MappingProxyType(colors)


# Every v2 name: "<ramp>_<n>" and "char_<who>_<slot>".
V2: Mapping[str, str] = _build_v2()

_V2_UI_RAMPS: tuple[str, ...] = (
    "void", "lamp", "bone", "ash", "wood", "parchment", "ink", "blood", "hp", "rage", "echo", "glow",
    "party_teal", "party_rose", "party_lime",
    "rim_storm", "rim_fire", "rim_frost", "rim_steel", "rim_brass", "rim_rare", "rim_epic", "rarity_v2",
    "tab", "ult", "sunset",
)

# Which ramps (and character palettes) a v2 canvas may use, by set id.
V2_SETS: Mapping[str, tuple[str, ...]] = MappingProxyType({
    "ui": _V2_UI_RAMPS,
    "collapsed_mines": ("mine_floor", "mine_stone", "mine_stone_shade", "timber", "copper", "iron_v2", "crate", "rubble",
                        "gas", "danger", "glow", "lamp", "char_wren", "char_kestrel", "char_ivy", "char_brann", "char_hollow_miner"),
    "town": ("grass", "leaf", "fruit", "flowers", "cobble", "dirt", "plaster", "plank", "roof_red", "roof_teal", "foundation",
             "window", "water", "lamp_iron", "night", "glow", "wood", "char_wren", "char_hilde"),
})


def v2_ramp(name: str) -> tuple[str, ...]:
    """A v2 ramp as palette names, light -> dark: v2_ramp("lamp") is
    ("lamp_0", ..., "lamp_5")."""
    if name not in V2_RAMPS:
        raise KeyError(name)
    return tuple(f"{name}_{i}" for i in range(len(V2_RAMPS[name])))


def character(who: str) -> dict[str, str]:
    """BODY template mapping for one character: row char -> palette name, ready
    for pixel.sprite_from_rows."""
    if who not in V2_CHARACTERS:
        raise KeyError(who)
    return {ch: f"char_{who}_{slot}" for ch, slot in zip(CHARACTER_CHARS, CHARACTER_SLOTS, strict=True)}


def v2_colors(set_id: str) -> dict[str, str]:
    """Names a v2 canvas for `set_id` ("ui", "collapsed_mines", "town")
    resolves: its ramps and characters plus the two accents."""
    if set_id not in V2_SETS:
        raise KeyError(set_id)
    out: dict[str, str] = dict(ACCENT)
    for entry in V2_SETS[set_id]:
        if entry.startswith("char_"):
            who = entry[len("char_"):]
            out.update({f"char_{who}_{slot}": v for slot, v in zip(CHARACTER_SLOTS, V2_CHARACTERS[who], strict=True)})
        else:
            out.update({name: V2[name] for name in v2_ramp(entry)})
    return out


def v2_rgb(set_id: str) -> frozenset[tuple[int, int, int]]:
    """Allowed colors for build_all.py's palette check on a v2 generator."""
    return frozenset(rgb_set(v2_colors(set_id).values()))


def _build_named() -> Mapping[str, str]:
    """GLOBAL plus the UI, RARITY and ELEMENT tables. Names must not collide."""
    named: dict[str, str] = dict(GLOBAL)
    for table in (UI, RARITY, ELEMENT):
        for name, value in table.items():
            if name in named:
                raise ValueError(f"palette name collision: {name}")
            named[name] = value
    return MappingProxyType(named)


# Every unqualified name a generator can use outside a biome context.
NAMED: Mapping[str, str] = _build_named()


def _build_all() -> Mapping[str, str]:
    colors: dict[str, str] = dict(NAMED)
    for b in _BIOMES:
        for name, value in b.biome_only.items():
            colors[b.qualified(name)] = value
    for name, value in V2.items():
        if name in colors:
            raise ValueError(f"palette name collision: {name}")
        colors[name] = value
    return MappingProxyType(colors)


# NAMED, every biome-only color under "<biome>.<name>", and every v2 name.
# pixel.Canvas's default.
ALL: Mapping[str, str] = _build_all()


def biome(biome_id: str) -> BiomePalette:
    """Raises KeyError for an unknown id."""
    return BIOMES[biome_id]


def colors_for(biome_id: str | None = None) -> dict[str, str]:
    """The names a Canvas resolves: a biome's names plus NAMED, or ALL."""
    if biome_id is None:
        return dict(ALL)
    return {**NAMED, **biome(biome_id).names}


def rgb(hex_value: str) -> tuple[int, int, int]:
    value = hex_value.lstrip("#")
    if len(value) != 6:
        raise ValueError(f"expected #RRGGBB, got {hex_value!r}")
    return (int(value[0:2], 16), int(value[2:4], 16), int(value[4:6], 16))


def rgb_set(hex_values: Iterable[str]) -> set[tuple[int, int, int]]:
    return {rgb(h) for h in hex_values}


def all_rgb() -> frozenset[tuple[int, int, int]]:
    """Every color in ALL as RGB: the loosest allowed set for build_all.py."""
    return frozenset(rgb_set(ALL.values()))


def all_hex() -> list[str]:
    """Every hex value this module exposes, deduplicated, in definition order."""
    values: list[str] = list(GLOBAL.values())
    for b in _BIOMES:
        values.extend(b.biome_only.values())
    for table in (UI, RARITY, ELEMENT):
        values.extend(table.values())
    values.extend(V2.values())
    return list(dict.fromkeys(values))
