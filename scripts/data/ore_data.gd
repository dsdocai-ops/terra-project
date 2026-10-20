class_name OreData
extends ContentData
## One ore type: the resource a biome mines and an elite, mini-boss or biome
## boss pays out. Owned by run-economy (W4-B8, goal G14). Sync: none (data).
##
## SPEC-run-economy, "Currencies": "Ore | mining nodes (interactable, 3 hits
## with any attack, Wren +25%), elites 1, mini-boss 3, biome boss 6, always the
## biome's ore: copper, iron, crystal, pearl, ember_ore, heartstone | shared".
## SPEC-run-economy, "Data model": "`OreData extends ContentData` under
## `data/ore/` (6)." SPEC-biomes carries the same six in its biome table
## ("| # | Biome | Floors | Ore |"), which is what `biome_index` records.
##
## The class adds one field and nothing else: `id`, `display_name` and `icon`
## come from `ContentData`, the id is the snake_case file name
## (`data/ore/copper.tres` -> `copper`), and the amounts are `OrePayout`'s
## constants rather than per-file numbers, because the spec states them once for
## all ore rather than once per ore.
##
## A biome's ore is read through `OrePayout.id_for_biome()` / `load_ore()`, which
## scan this folder — so a new ore is one `.tres` and no code, and the folder
## itself is the table's source of truth (SPEC-project: content is data).

## Which biome this ore comes from, 1 to 6, matching `RunState.biome_index` and
## `BiomePlaceholder.id`. The spec's biome table gives exactly one ore per biome,
## so this is unique across the six files; `OrePayout.id_for_biome()` is the read
## that relies on it.
@export var biome_index: int = 1
