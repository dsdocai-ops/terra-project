"""Master palette for Sinkhole's isometric pixel art.

Every generator takes its colours from here by name; a literal RGB in a sprite
script is a review failure (SPEC-art-audio). Biome palettes are the locked ones
from the spec; the first biome (collapsed_mines) is the one drawn so far.
"""


def hex_rgb(value):
    value = value.lstrip("#")
    return (int(value[0:2], 16), int(value[2:4], 16), int(value[4:6], 16), 255)


OUTLINE = hex_rgb("#1A1420")
WHITE = hex_rgb("#FFFFFF")
CLEAR = (0, 0, 0, 0)
SHADOW = (14, 10, 18, 110)

# Ramps run light -> dark so shading code can index by "how lit is this pixel".
RAMPS = {
    "rock": [hex_rgb(c) for c in ("#8C6A4C", "#6B4A32", "#553A28", "#3D2A1E")],
    "wall": [hex_rgb(c) for c in ("#6E5238", "#4A3626", "#382819", "#271B12")],
    "timber": [hex_rgb(c) for c in ("#B07A44", "#8A5A30", "#663F22", "#472C18")],
    "iron": [hex_rgb(c) for c in ("#B7B2B8", "#8A8590", "#5E5A66", "#3A3642")],
    "copper": [hex_rgb(c) for c in ("#F0A060", "#C8783A", "#97532A", "#63361E")],
    "gold": [hex_rgb(c) for c in ("#FFE680", "#F2C14E", "#C48A2A", "#85561A")],
    "cloth": [hex_rgb(c) for c in ("#B9623A", "#8A4B2A", "#663720", "#44251A")],
    "skin": [hex_rgb(c) for c in ("#F1C9A0", "#D9A57A", "#B3805A", "#845A40")],
    "hat": [hex_rgb(c) for c in ("#FFD84D", "#E0B040", "#B58628", "#7A5A1A")],
    "echo": [hex_rgb(c) for c in ("#E8C8FF", "#B58AF0", "#8A5AD0", "#5A3796")],
    "relic": [hex_rgb(c) for c in ("#BFE9FF", "#7FD6FF", "#4A9AD0", "#2C5F8A")],
    "ore": [hex_rgb(c) for c in ("#F7C292", "#D98B4A", "#A65F2E", "#6E3C1C")],
    "blood": [hex_rgb(c) for c in ("#FF8A7A", "#D83A3A", "#9B2424", "#5E1616")],
}

LANTERN = hex_rgb("#FFB347")
LANTERN_WARM = hex_rgb("#FFD9A0")
PIT_DEEP = hex_rgb("#0B080E")
PIT_MID = hex_rgb("#1A1420")
PIT_RIM = hex_rgb("#2E2330")


def mix(a, b, t):
    return tuple(int(round(a[i] + (b[i] - a[i]) * t)) for i in range(3)) + (255,)


def ramp_from(base_hex):
    """Light -> dark 4-step ramp around one base colour."""
    base = hex_rgb(base_hex)
    return [mix(base, WHITE, 0.28), base, mix(base, (0, 0, 0, 255), 0.30), mix(base, (0, 0, 0, 255), 0.55)]


# Locked biome palettes (SPEC-art-audio): ground, wall and the accents each
# biome's decoration is drawn with.
BIOMES = {
    "collapsed_mines": {"ground": "#6B4A32", "wall": "#4A3626", "accent1": "#C8783A", "accent2": "#FFB347", "light": "#FFD9A0"},
    "fungal_caverns": {"ground": "#2E4A48", "wall": "#1F3230", "accent1": "#9B5DE5", "accent2": "#5EF2E0", "light": "#A8FFF4"},
    "crystal_hollows": {"ground": "#4A5A78", "wall": "#2F3A52", "accent1": "#F28CC9", "accent2": "#8CE8FF", "light": "#E8F6FF"},
    "drowned_city": {"ground": "#2C4A5E", "wall": "#1C3240", "accent1": "#5FA36A", "accent2": "#E6E1D3", "light": "#6FA8C9"},
    "ember_forge": {"ground": "#3A2E2E", "wall": "#241C1C", "accent1": "#FF6A1F", "accent2": "#FFD23F", "light": "#FF9A4A"},
    "the_heart": {"ground": "#5A2A3A", "wall": "#3A1A28", "accent1": "#8A2BE2", "accent2": "#E8DCC8", "light": "#FF3C6E"},
}
