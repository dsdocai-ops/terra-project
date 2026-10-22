# Review queue

Changes Claude made to `project.godot` and `scripts/data/` without asking.
Logged automatically by `.claude/hooks/review_log.py`. Tick one box per entry.

### 2026-10-21 20:22 · `project.godot` · modified

- Tool: Bash: `git checkout -- project.godot && git fetch --all --prune && git pull --ff-only && git log --oneline main..feat/asset-tooling && echo ---- && git log --oneline main..origin/feat/ui-hud-pixel-art-pass &...`
- Reason: Reverted an accidental local key reorder in project.godot so main matches origin; no settings changed.
- Decision: [x] keep  [ ] revert

```diff
--- a/project.godot
+++ b/project.godot
@@ -11,8 +11,8 @@
 [application]
 
 config/name="Sinkhole"
+config/features=PackedStringArray("4.7", "GL Compatibility")
 run/main_scene="res://scenes/main/main.tscn"
-config/features=PackedStringArray("4.7", "GL Compatibility")
 config/icon="res://icon.svg"
 
 [autoload]
```

### 2026-10-21 20:24 · `scripts/data/loot_table.gd` · added

- Tool: Bash: `git merge --no-ff --no-commit origin/feat/ui-hud-pixel-art-pass 2>&1 | tail -30; echo "=== conflicts:"; git diff --name-only --diff-filter=U`
- Reason: Brought in by merging origin/feat/ui-hud-pixel-art-pass (Dev B's reviewed run-economy and relics work); not an edit made in this session.
- Decision: [x] keep  [ ] revert

```diff
--- a/scripts/data/loot_table.gd
+++ b/scripts/data/loot_table.gd
@@ -0,0 +1,193 @@
+class_name LootTable
+extends Resource
+## A weighted drop table: the one roll every chest, breakable, enemy and shop
+## uses. Owned by run-economy (W4-B8, goal G13).
+##
+## SPEC-run-economy, "Chests, breakables, mining nodes": "`LootTable` Resource:
+## weighted entries `{kind, id or rarity, weight, min, max}`. Chest rarity tiers
+## common/rare/legendary; ... Luck stat raises rarity rolls: `rarity_roll +=
+## LUCK * 0.01`." Those two sentences are the whole of this file.
+##
+## An entry names its **kind** (`Pickup.KINDS`) and then either a fixed content
+## **id** (an ore type, a relic id, a rune) or a **rarity** — never both. `min`
+## and `max` bound the amount the drop carries; `min == max` is a fixed amount.
+## `weight` decides how often the entry comes up, so the table's shares are the
+## entries' weights and nothing else.
+##
+## A rarity entry's own rarity is a **floor**: the drop's tier is the higher of
+## that floor and the table's own rarity roll, so a rare chest can still yield an
+## epic and a common entry never downgrades to nothing. The rarity roll is the
+## spec's own: `rarity_roll = rng.randf() + LUCK * 0.01`, clamped to 0..1 and
+## mapped over `RelicData`'s four Shrine tier weights (common 60, rare 28, epic
+## 10, legendary 2). The formula lives in `RelicRoller.shifted_roll()` and
+## `RelicRoller.rarity_for_roll()` — the same sentence of SPEC-run-economy drives
+## both, so this file delegates rather than keeping a second copy that could
+## drift. Cursed is never in the tier table: it is taken at an altar, not rolled.
+##
+## `entries` is the exported boundary: an `Array[Dictionary]` as authored in a
+## `.tres`. It is converted immediately by `entry_list()` into typed `Entry`
+## objects (SPEC-project C12: untyped data only at the boundary), which is what
+## every roll reads. No caching, because a table is a handful of entries and a
+## stale copy would outlive an edit.
+##
+## Sync: none (data). The rolls themselves are the host's (SPEC-run-economy,
+## "Multiplayer ownership": "loot rolls ... host"); a client never rolls a table.
+
+## `Entry.rarity`'s "this entry names an id instead" sentinel.
+const RARITY_NONE: int = -1
+
+## How much of the rarity table one point of `Stat.LUCK` buys, from
+## SPEC-run-economy's own term: "`rarity_roll += LUCK * 0.01`". Taken from
+## `RelicRoller`, which owns the formula, so the two cannot disagree.
+const LUCK_SHIFT_PER_POINT: float = RelicRoller.LUCK_SHIFT_PER_POINT
+
+## SPEC-run-economy: "Chest rarity tiers common/rare/legendary", in that order.
+const CHEST_TIER_COMMON: int = RelicData.Rarity.COMMON
+const CHEST_TIER_RARE: int = RelicData.Rarity.RARE
+const CHEST_TIER_LEGENDARY: int = RelicData.Rarity.LEGENDARY
+const CHEST_TIERS: Array[int] = [CHEST_TIER_COMMON, CHEST_TIER_RARE, CHEST_TIER_LEGENDARY]
+
+## The raw entries, authored in the `.tres`: `{kind, id or rarity, weight, min,
+## max}`. Converted by `entry_list()` before anything reads them.
+@export var entries: Array[Dictionary] = []
+
+
+## One entry after the boundary conversion. Typed so a roll reads fields rather
+## than dictionary keys, and so `rarity`/`id` cannot both be set by accident.
+class Entry extends RefCounted:
+	## One of `Pickup.KINDS`.
+	var kind: StringName = &""
+	## A fixed content id, or empty when the entry rolls a rarity.
+	var id: StringName = &""
+	## `LootTable.RARITY_NONE`, or the floor tier of a rarity roll.
+	var rarity: int = -1
+	## Relative frequency among the table's entries.
+	var weight: float = 1.0
+	var min_amount: int = 1
+	var max_amount: int = 1
+
+	## True when this entry yields a rarity rather than a fixed id.
+	func rolls_rarity() -> bool:
+		return rarity != LootTable.RARITY_NONE
+
+
+## `raw` converted to a typed `Entry`. Missing fields take the shape's defaults
+## (weight 1, amount 1, no id, no rarity); a reversed amount range is ordered
+## rather than rejected, so one bad range cannot make a table unrollable.
+static func parse_entry(raw: Dictionary) -> Entry:
... 116 more lines, see `git diff -- scripts/data/loot_table.gd`
```

### 2026-10-21 20:24 · `scripts/data/ore_data.gd` · added

- Tool: Bash: `git merge --no-ff --no-commit origin/feat/ui-hud-pixel-art-pass 2>&1 | tail -30; echo "=== conflicts:"; git diff --name-only --diff-filter=U`
- Reason: Brought in by merging origin/feat/ui-hud-pixel-art-pass (Dev B's reviewed run-economy and relics work); not an edit made in this session.
- Decision: [x] keep  [ ] revert

```diff
--- a/scripts/data/ore_data.gd
+++ b/scripts/data/ore_data.gd
@@ -0,0 +1,27 @@
+class_name OreData
+extends ContentData
+## One ore type: the resource a biome mines and an elite, mini-boss or biome
+## boss pays out. Owned by run-economy (W4-B8, goal G14). Sync: none (data).
+##
+## SPEC-run-economy, "Currencies": "Ore | mining nodes (interactable, 3 hits
+## with any attack, Wren +25%), elites 1, mini-boss 3, biome boss 6, always the
+## biome's ore: copper, iron, crystal, pearl, ember_ore, heartstone | shared".
+## SPEC-run-economy, "Data model": "`OreData extends ContentData` under
+## `data/ore/` (6)." SPEC-biomes carries the same six in its biome table
+## ("| # | Biome | Floors | Ore |"), which is what `biome_index` records.
+##
+## The class adds one field and nothing else: `id`, `display_name` and `icon`
+## come from `ContentData`, the id is the snake_case file name
+## (`data/ore/copper.tres` -> `copper`), and the amounts are `OrePayout`'s
+## constants rather than per-file numbers, because the spec states them once for
+## all ore rather than once per ore.
+##
+## A biome's ore is read through `OrePayout.id_for_biome()` / `load_ore()`, which
+## scan this folder — so a new ore is one `.tres` and no code, and the folder
+## itself is the table's source of truth (SPEC-project: content is data).
+
+## Which biome this ore comes from, 1 to 6, matching `RunState.biome_index` and
+## `BiomePlaceholder.id`. The spec's biome table gives exactly one ore per biome,
+## so this is unique across the six files; `OrePayout.id_for_biome()` is the read
+## that relies on it.
+@export var biome_index: int = 1
```

### 2026-10-21 20:24 · `scripts/data/relic_data.gd` · added

- Tool: Bash: `git merge --no-ff --no-commit origin/feat/ui-hud-pixel-art-pass 2>&1 | tail -30; echo "=== conflicts:"; git diff --name-only --diff-filter=U`
- Reason: Brought in by merging origin/feat/ui-hud-pixel-art-pass (Dev B's reviewed run-economy and relics work); not an edit made in this session.
- Decision: [x] keep  [ ] revert

```diff
--- a/scripts/data/relic_data.gd
+++ b/scripts/data/relic_data.gd
@@ -0,0 +1,104 @@
+class_name RelicData
+extends ContentData
+## One relic: a run-only item whose behaviour is an `Effect` script.
+## Owned by relics (W4-B5). Sync: none (data).
+##
+## SPEC-relics "RelicData" fixes the field list and the two enums; the design
+## doc sections 9.1 to 9.3 are the source of every display name, description and
+## balance number, and a description's numbers are the source of truth for the
+## effect script's constants. `data/relics/<id>.tres` + an optional
+## `scripts/effects/relics/<id>.gd`.
+##
+## `id`, `display_name`, `tags`, `effect_script` and `icon` are inherited from
+## `ContentData` unchanged — this class adds no field of the same name, so no
+## saved `.tres` of either type moves because of it. `effect_script` must be a
+## script that extends `Effect`; `tags` holds 1 or 2 entries of the `Tags`
+## vocabulary.
+##
+## `Rarity` and `Kind` are this class's own enums and their declaration order is
+## the value serialised into every relic `.tres`, so reordering either one would
+## silently re-map all 88 relics. `tests/unit/test_relic_data.gd` pins the order
+## and reads the id list and the weights back against the documents they come
+## from.
+##
+## The rolls that read these tables are host-only (SPEC-relics "Multiplayer
+## ownership"); nothing in this file decides anything at runtime.
+
+enum Rarity {
+	COMMON,
+	RARE,
+	EPIC,
+	LEGENDARY,
+	CURSED,
+}
+
+enum Kind {
+	PASSIVE,
+	ACTIVE,
+	CURSED,
+}
+
+## Drop tier, used by `RelicRoller`'s rarity stage and by the HUD's colour.
+@export var rarity: Rarity = Rarity.COMMON
+## `PASSIVE`, `ACTIVE` (the C and B slots) or `CURSED` (Cursed Altars only).
+@export var kind: Kind = Kind.PASSIVE
+## From the design doc, with `{value}` placeholders filled from the effect
+## script's constants by the choice popup.
+@export var description: String = ""
+## How many copies a build may hold; 1 for everything that does not stack
+## (Second Wind, most relics), more for the stacking ones (Lucky Coin).
+@export var max_stacks: int = 1
+## Actives only: the slot's cooldown in seconds and the charges it refills to.
+@export var active_cooldown: float = 0.0
+@export var active_charges: int = 0
+## Drop weight *within* the relic's rarity, rolled by `RelicRoller`.
+@export var weight: float = 1.0
+
+## The Shrine rarity tiers' weights, from SPEC-relics: "common 60, rare 28,
+## epic 10, legendary 2, adjusted by `Stat.LUCK` and Lucky Find". `CURSED` has
+## no weight because cursed relics never roll at a Shrine.
+const RARITY_WEIGHT_COMMON: int = 60
+const RARITY_WEIGHT_RARE: int = 28
+const RARITY_WEIGHT_EPIC: int = 10
+const RARITY_WEIGHT_LEGENDARY: int = 2
+
+## The tier weights keyed by `Rarity`. `RelicRoller`'s rarity stage reads this
+## through `roll_weight()`, so the numbers have one home.
+const RARITY_ROLL_WEIGHTS: Dictionary[int, int] = {
+	Rarity.COMMON: RARITY_WEIGHT_COMMON,
+	Rarity.RARE: RARITY_WEIGHT_RARE,
+	Rarity.EPIC: RARITY_WEIGHT_EPIC,
+	Rarity.LEGENDARY: RARITY_WEIGHT_LEGENDARY,
+}
+
+## Week 4's twenty relics — design doc 9.1 nos. 1 to 20, in that order, each id
+## being the snake_case file name it will have under `data/relics/`. This is the
+## one source of truth for the batch's count, so the content goal and the
+## data-driven test cannot disagree about what "the 20" means.
... 27 more lines, see `git diff -- scripts/data/relic_data.gd`
```
