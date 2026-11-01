"""v3 cast: the four delvers, town NPCs and the humanoid enemies, as Hero options.
Base colours only; every other tone is derived by core.ramp()."""

from __future__ import annotations

SK = {"fair": "#f8dcc0", "light": "#f4c8a0", "tan": "#dca07a", "brown": "#b07848", "deep": "#86563a", "pale": "#e0d8d0", "grey": "#a8b0a0"}

CHARACTERS: dict[str, dict] = {
    "wren": {"skin": SK["light"], "hair": "#c4582c", "hairStyle": "fringe", "hat": "miner", "hatC": "#f0b830", "shirt": "#f0e2c0",
             "pants": "#3e6ea8", "cloth": [("overalls", None)], "boots": "#7a4a2a", "eye": "#3a6a3a", "item": "pick"},
    "brann": {"skin": SK["tan"], "hair": "#b8b0a8", "hairStyle": "baldsides", "beard": "#d8d2ca", "shirt": "#b8423a",
              "cloth": [("plaid", "#7a2a2a"), ("vest", "#6a4a32")], "pants": "#6a5a44", "boots": "#4a3020", "eye": "#4a3a2a", "item": "hammer"},
    "ivy": {"skin": SK["fair"], "hair": "#f8e090", "hairStyle": "bob", "hat": "cap", "hatC": "#4a8a44", "shirt": "#6aa04a",
            "cloth": [("scarf", "#f09838")], "pants": "#6a5038", "boots": "#6a3e22", "eye": "#3a5aa0", "item": "lanternstaff"},
    "kestrel": {"skin": SK["brown"], "hair": "#2e2438", "hairStyle": "spiky", "hat": "bandana", "hatC": "#d8483a", "shirt": "#8a5a38",
                "cape": "#4a3c64", "cloth": [("scarf", "#d8483a")], "pants": "#3c3a50", "boots": "#2e2428", "eye": "#c88a2a",
                "item": "dagger", "item2": "dagger"},
}

NPCS: dict[str, dict] = {
    "hilde": {"skin": SK["light"], "hair": "#9a9aaa", "hairStyle": "bun", "shirt": "#7a2a54", "cloth": [("robe", "#7a2a54")], "boots": "#3a2a20", "item": "book", "itemC": "#4a3a7a"},
    "gruff": {"skin": SK["tan"], "hair": "#3a2a20", "hairStyle": "baldsides", "beard": "#6a3a22", "shirt": "#9a4a3a", "cloth": [("apron", "#4a3a2a")], "pants": "#4a3a2a", "boots": "#2a1a10", "item": "hammer"},
    "moss": {"skin": SK["fair"], "hair": "#7ab05a", "hairStyle": "spiky", "hat": "goggles", "hatC": "#c8a048", "shirt": "#ece4cc", "cloth": [("apron", "#5a8a4a")], "pants": "#5a4a3a", "boots": "#4a3a2a", "item": "orb", "itemC": "#9af05a"},
    "pip": {"skin": SK["brown"], "hair": "#4a2a1a", "hairStyle": "short", "hat": "cap", "hatC": "#3a6ab0", "shirt": "#e8c040", "cloth": [("overalls", None)], "pants": "#7a5a3a", "boots": "#4a3020", "item": "book", "itemC": "#e8d8b0"},
    "ash": {"skin": SK["light"], "hair": "#a0a0a8", "hairStyle": "long", "hat": "veil", "hatC": "#4a4a5e", "shirt": "#4a4a5e", "cloth": [("robe", "#4a4a5e")], "boots": "#2a2a30", "item": "lantern"},
    "tom": {"skin": SK["tan"], "hair": "#e8e0d8", "hairStyle": "baldsides", "mustache": "#e8e0d8", "shirt": "#ece4cc", "cloth": [("vest", "#7a3a2a"), ("apron", "#f2eee2")], "pants": "#4a3a2a", "boots": "#3a2a1a"},
    "vesper": {"skin": "#c0b0d0", "hair": "#2a1a3a", "hairStyle": "long", "hat": "tophat", "hatC": "#2a1a3a", "cape": "#2a1a3a", "shirt": "#4a2a5a", "pants": "#2a1a3a", "boots": "#1a1020", "glow": "#d07af0", "noBlush": True},
    "nettie": {"skin": SK["light"], "hair": "#c86a3a", "hairStyle": "ponytail", "shirt": "#5a4a6a", "cloth": [("vest", "#3a3a4a")], "pants": "#3a3a4a", "boots": "#2a2a2a", "item": "dagger"},
    "cogsworth": {"skin": SK["tan"], "hair": "#8a8a8a", "hairStyle": "short", "mustache": "#8a8a8a", "hat": "goggles", "hatC": "#c8a048", "shirt": "#6a7a8a", "cloth": [("apron", "#5a4a3a")], "pants": "#4a4a5a", "boots": "#3a3a3a", "item": "wrench", "itemC": "#8a94a4"},
    "mortimer": {"skin": "#dcd0c4", "hair": "#4a4a4a", "hairStyle": "short", "hat": "tophat", "hatC": "#2a2a2a", "shirt": "#3a3a3a", "cloth": [("vest", "#2a2a2a")], "pants": "#2a2a2a", "boots": "#1a1a1a", "item": "pick", "noBlush": True},
    "elian": {"skin": SK["deep"], "hair": "#1a1a1a", "hairStyle": "short", "shirt": "#ece4d4", "cloth": [("robe", "#ece4d4")], "boots": "#7a6040", "item": "lantern"},
}

HUMANOIDS: dict[str, dict] = {
    "hollow_miner": {"skin": SK["grey"], "hair": "#4a4a3a", "hairStyle": "fringe", "hat": "miner", "hatC": "#7a7a6a", "shirt": "#6a6a5a", "cloth": [("overalls", None)], "pants": "#4a5a6a", "boots": "#3a3a3a", "item": "pick", "glow": "#c070ff", "noBlush": True},
    "dynamite_goblin": {"skin": "#7ab05a", "ears": "#7ab05a", "hair": "#3a2a1a", "hairStyle": "spiky", "shirt": "#8a5a3a", "pants": "#5a4a3a", "boots": "#3a2a1a", "item": "dynamite", "itemC": "#d8402a", "glow": "#ffe04a", "noBlush": True},
    "deepkin": {"skin": "#5aa0a0", "ears": "#3a8a9a", "hair": "#3a7a8a", "hairStyle": "baldsides", "shirt": "#3a6a7a", "pants": "#2a4a5a", "boots": "#2a3a4a", "item": "spear", "glow": "#ffe04a", "noBlush": True},
    "drowned_priest": {"skin": "#7ab0a8", "hat": "hood", "hatC": "#2a4a5a", "shirt": "#2a4a5a", "cloth": [("robe", "#2a4a5a")], "boots": "#1a2a3a", "item": "staff", "itemC": "#7af0d0", "glow": "#7af0d0", "noBlush": True},
    "siren": {"skin": "#a8d8d0", "hair": "#3ab0a0", "hairStyle": "long", "ears": "#3a9a8a", "shirt": "#3a8a8a", "tail": "#3a9a8a", "noLegs": True, "glow": "#f07ad0", "noBlush": True},
    "ashen_smith": {"skin": "#9a948e", "hair": "#4a4a4a", "hairStyle": "baldsides", "beard": "#5a5a5a", "shirt": "#4a4440", "cloth": [("apron", "#2a2420")], "pants": "#3a3430", "boots": "#1a1a1a", "item": "hammer", "itemC": "#ff8a2a", "glow": "#ff8a2a", "noBlush": True},
    "heart_guard": {"skin": "#6a2a3a", "hat": "helm", "hatC": "#6a2a3a", "plume": "#ff4a6a", "shirt": "#3a1a2a", "cloth": [("armor", "#7a2a3a")], "pants": "#2a1a24", "boots": "#1a1018", "shield": "#9a2a4a", "item": "spear", "itemC": "#ff4a6a", "glow": "#ff4a6a", "noBlush": True},
    "echo": {**CHARACTERS["wren"], "tint": "#1a0e28", "tintAmt": 0.72, "glow": "#c070ff"},
}
