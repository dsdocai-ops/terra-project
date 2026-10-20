class_name Tags
extends RefCounted
## The closed tag vocabulary every piece of content is classified by, from
## `specs/SPEC-effect-system.md` "Tags and synergies". Owned by effect-system
## (W4-B2).
##
## `ContentData.tags` holds 1 or 2 of these; `EffectHost.list_tags()` counts
## them across the effects attached to a player and `relics` evaluates its
## `SynergyData` requirements against that count. The set is closed on purpose:
## a synergy that matches on a free-text tag would silently never fire, so an
## unknown tag is a data bug the tests catch rather than a second vocabulary.
##
## `ALL` is the vocabulary in the spec's own order, and `is_valid()` is the one
## check every data-driven test uses.
##
## Sync: none — a constant vocabulary with no state.

const FIRE: StringName = &"fire"
const FROST: StringName = &"frost"
const STORM: StringName = &"storm"
const SHADOW: StringName = &"shadow"
const POISON: StringName = &"poison"
const EARTH: StringName = &"earth"
const BLOOD: StringName = &"blood"
const VOID: StringName = &"void"
const DODGE: StringName = &"dodge"
const ON_HIT: StringName = &"on_hit"
const ON_KILL: StringName = &"on_kill"
const ON_DAMAGED: StringName = &"on_damaged"
const CRIT: StringName = &"crit"
const ABILITY: StringName = &"ability"
const MOVEMENT: StringName = &"movement"
const ECONOMY: StringName = &"economy"
const TRANSFORMATION: StringName = &"transformation"
const CURSED: StringName = &"cursed"
const ACTIVE: StringName = &"active"

## The whole vocabulary, in the spec's order. 19 tags.
const ALL: Array[StringName] = [
	FIRE,
	FROST,
	STORM,
	SHADOW,
	POISON,
	EARTH,
	BLOOD,
	VOID,
	DODGE,
	ON_HIT,
	ON_KILL,
	ON_DAMAGED,
	CRIT,
	ABILITY,
	MOVEMENT,
	ECONOMY,
	TRANSFORMATION,
	CURSED,
	ACTIVE,
]


## True when `tag` is one of the 19 tags above. Callers pass the tag straight
## out of `ContentData.tags`, so an empty or invented tag returns false rather
## than raising.
static func is_valid(tag: StringName) -> bool:
	return ALL.has(tag)
