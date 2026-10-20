class_name RelicData
extends ContentData
## One relic: a run-only item whose behaviour is an `Effect` script.
## Owned by relics (W4-B5). Sync: none (data).
##
## SPEC-relics "RelicData" fixes the field list and the two enums; the design
## doc sections 9.1 to 9.3 are the source of every display name, description and
## balance number, and a description's numbers are the source of truth for the
## effect script's constants. `data/relics/<id>.tres` + an optional
## `scripts/effects/relics/<id>.gd`.
##
## `id`, `display_name`, `tags`, `effect_script` and `icon` are inherited from
## `ContentData` unchanged — this class adds no field of the same name, so no
## saved `.tres` of either type moves because of it. `effect_script` must be a
## script that extends `Effect`; `tags` holds 1 or 2 entries of the `Tags`
## vocabulary.
##
## `Rarity` and `Kind` are this class's own enums and their declaration order is
## the value serialised into every relic `.tres`, so reordering either one would
## silently re-map all 88 relics. `tests/unit/test_relic_data.gd` pins the order
## and reads the id list and the weights back against the documents they come
## from.
##
## The rolls that read these tables are host-only (SPEC-relics "Multiplayer
## ownership"); nothing in this file decides anything at runtime.

enum Rarity {
	COMMON,
	RARE,
	EPIC,
	LEGENDARY,
	CURSED,
}

enum Kind {
	PASSIVE,
	ACTIVE,
	CURSED,
}

## Drop tier, used by `RelicRoller`'s rarity stage and by the HUD's colour.
@export var rarity: Rarity = Rarity.COMMON
## `PASSIVE`, `ACTIVE` (the C and B slots) or `CURSED` (Cursed Altars only).
@export var kind: Kind = Kind.PASSIVE
## From the design doc, with `{value}` placeholders filled from the effect
## script's constants by the choice popup.
@export var description: String = ""
## How many copies a build may hold; 1 for everything that does not stack
## (Second Wind, most relics), more for the stacking ones (Lucky Coin).
@export var max_stacks: int = 1
## Actives only: the slot's cooldown in seconds and the charges it refills to.
@export var active_cooldown: float = 0.0
@export var active_charges: int = 0
## Drop weight *within* the relic's rarity, rolled by `RelicRoller`.
@export var weight: float = 1.0

## The Shrine rarity tiers' weights, from SPEC-relics: "common 60, rare 28,
## epic 10, legendary 2, adjusted by `Stat.LUCK` and Lucky Find". `CURSED` has
## no weight because cursed relics never roll at a Shrine.
const RARITY_WEIGHT_COMMON: int = 60
const RARITY_WEIGHT_RARE: int = 28
const RARITY_WEIGHT_EPIC: int = 10
const RARITY_WEIGHT_LEGENDARY: int = 2

## The tier weights keyed by `Rarity`. `RelicRoller`'s rarity stage reads this
## through `roll_weight()`, so the numbers have one home.
const RARITY_ROLL_WEIGHTS: Dictionary[int, int] = {
	Rarity.COMMON: RARITY_WEIGHT_COMMON,
	Rarity.RARE: RARITY_WEIGHT_RARE,
	Rarity.EPIC: RARITY_WEIGHT_EPIC,
	Rarity.LEGENDARY: RARITY_WEIGHT_LEGENDARY,
}

## Week 4's twenty relics — design doc 9.1 nos. 1 to 20, in that order, each id
## being the snake_case file name it will have under `data/relics/`. This is the
## one source of truth for the batch's count, so the content goal and the
## data-driven test cannot disagree about what "the 20" means.
const WEEK_4_IDS: Array[StringName] = [
	&"ember_boots",
	&"storm_sandals",
	&"mirror_step",
	&"frostwalkers",
	&"ghost_wrap",
	&"rebound_spring",
	&"echo_blade",
	&"spark_plug",
	&"hungry_steel",
	&"venom_gland",
	&"splitting_shot",
	&"gravity_stone",
	&"leech_fang",
	&"rune_of_ricochet",
	&"volatile_core",
	&"soul_jar",
	&"bloodthirst",
	&"corpse_bloom",
	&"domino",
	&"trophy_belt",
]


## The Shrine roll weight of `rarity`, or 0 for one that never rolls there.
static func roll_weight(rarity: Rarity) -> int:
	return RARITY_ROLL_WEIGHTS.get(rarity, 0)
