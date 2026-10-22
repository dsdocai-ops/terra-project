"""Master palette for every generated asset (specs/SPEC-art-audio.md, "Master palette").

Generators import colors from here by name. A literal RGB in a sprite script
is a review failure. All values are uppercase "#RRGGBB" strings; use rgb() or
rgb_set() to get tuples for Pillow.

Global set: 8 hue ramps x 5 steps (shadow, dark, base, light, highlight),
1 neutral ramp of 7 grays (neutral_0 darkest), and 2 pure accents. Ramps are
hue-shifted: shadows lean cool, highlights lean warm.

Each biome palette is a named 24-color selection from the global set plus up
to 8 biome-only colors. The biome-only colors are the five from the spec
table (ground base, wall base, accent 1, accent 2, light); the 3 free slots
are for the biome's first real tileset pass.

Changelog (a palette locks once the biome's first real tileset is approved;
edits after that are a human decision recorded here):
- 2026-10-19: created. Spec table colors (biome, UI, rarity, element, accents)
  copied from SPEC-art-audio and locked. Global ramps and biome selections are
  drafts until each biome's first tileset review.
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


@dataclass(frozen=True)
class BiomePalette:
    """One biome's colors. ground, wall, accent_1, accent_2, light are the spec
    table values; colors maps every name usable in this biome to its hex."""

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
    extra: Mapping[str, str] = field(default_factory=dict)

    @property
    def biome_only(self) -> dict[str, str]:
        """Colors not in the global set, by name. Accents and light are keyed
        by their spec names (copper, lantern, warm, ...)."""
        return {
            "ground": self.ground,
            "wall": self.wall,
            self.accent_1_name: self.accent_1,
            self.accent_2_name: self.accent_2,
            self.light_name: self.light,
            **self.extra,
        }

    @property
    def colors(self) -> dict[str, str]:
        return {**{name: GLOBAL[name] for name in self.selection}, **self.biome_only}

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
        + _neutral(1, 2, 3, 4, 5),
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
        + _neutral(3, 4, 5, 6),
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


def biome(biome_id: str) -> BiomePalette:
    """Raises KeyError for an unknown id."""
    return BIOMES[biome_id]


def rgb(hex_value: str) -> tuple[int, int, int]:
    value = hex_value.lstrip("#")
    if len(value) != 6:
        raise ValueError(f"expected #RRGGBB, got {hex_value!r}")
    return (int(value[0:2], 16), int(value[2:4], 16), int(value[4:6], 16))


def rgb_set(hex_values: Iterable[str]) -> set[tuple[int, int, int]]:
    return {rgb(h) for h in hex_values}


def all_hex() -> list[str]:
    """Every hex value this module exposes, deduplicated, in definition order."""
    values: list[str] = list(GLOBAL.values())
    for b in _BIOMES:
        values.extend(b.biome_only.values())
    for table in (UI, RARITY, ELEMENT):
        values.extend(table.values())
    return list(dict.fromkeys(values))
