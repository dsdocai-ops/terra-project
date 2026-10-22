class_name Scaling
extends RefCounted
## The run's difficulty curves: biome depth scaling, the per-floor enemy and
## elite budgets, the elite HP rule, and the co-op HP multiplier's single read.
## Owned by stats-status.
##
## SPEC-stats-status, "Scaling constants": "`Scaling` static class:
## `enemy_hp_mult(biome_index) = 1.12 ** (biome_index - 1)`, same for damage;
## `enemies_per_room(floor)`, `elite_chance(floor)`; elite base `+100% HP`;
## co-op HP multiplier comes from `NetworkManager`." Design doc 9.5: "Depth
## scaling: enemy HP and damage go up about 12% per biome, plus more enemies per
## room and more elites on deeper floors."
##
## Every member is a `const` or a static function: the class is never
## instantiated, and nothing here holds state. The two curves the design doc
## names without giving a formula — `enemies_per_room` and `elite_chance` — are
## the run's own shape, chosen to be monotonic across the floor range and clamped
## at both ends rather than to hit any particular number; the week-12 balance
## pass owns their tuning, exactly as SPEC-stats-status's "Open questions" says
## of the status table.
##
## Sync: host only in practice — every caller (`enemies-ai`'s `SpawnDirector` v2,
## a boss's spawn path) decides enemy numbers on the host, and the one input that
## depends on the session, the player count, is read through
## `NetworkManager.enemy_hp_multiplier()` rather than recomputed here, so the
## co-op curve has one owner. The curves themselves are constants, identical on
## every peer and needing no replication.
##
## Consumed by Dev A's `SpawnDirector` v2 and the elite affix work — **blocked on
## Dev A (W4-A1, W4-A2)** for the real caller, so nothing in a running build
## reads these yet. SPEC-floor-generation also names `Scaling.rune_room_chance`
## and `Scaling.modifier_chance`; those are floor-generation's room and modifier
## rolls and no Week 4 goal asks for them, so they are recorded as absent here
## rather than invented.

# --- biome depth ------------------------------------------------------------

## The first biome, and the index the spec's formula measures from.
const FIRST_BIOME: int = 1
## The design doc's "about 12% per biome", as a fraction.
const BIOME_STEP: float = 0.12
## `1 + BIOME_STEP`, i.e. the 1.12 of the spec's formula. Named once so the
## percentage the design doc states and the base the formula raises cannot drift
## apart.
const BIOME_HP_MULTIPLIER: float = 1.0 + BIOME_STEP

# --- floors -----------------------------------------------------------------

## The first floor, and the shallowest index either floor curve is defined for.
const FIRST_FLOOR: int = 1
## How deep the floor curves are defined. A deeper index is clamped to this, so
## a caller beyond the design doc's depth still reads a sane number rather than
## an extrapolated one.
const LAST_FLOOR: int = 30

## The enemies a combat room's budget starts at on floor 1.
const ENEMIES_PER_ROOM_BASE: int = 4
## How much that grows per floor. Four enemies on floor 1, one more every two
## floors, reaching the cap below on the deepest floor.
const ENEMIES_PER_ROOM_PER_FLOOR: float = 0.5
## The ceiling on a combat room's budget, so a pathologically deep index cannot
## ask for a room nobody can fight.
const ENEMIES_PER_ROOM_MAX: int = 18

## The chance a spawn slot on floor 1 rolls an elite.
const ELITE_CHANCE_BASE: float = 0.05
## How much that grows per floor.
const ELITE_CHANCE_PER_FLOOR: float = 0.004
## The ceiling on the elite chance, kept well under 1.0 because a floor that is
## nothing but elites is a floor modifier's business, not the depth curve's.
const ELITE_CHANCE_MAX: float = 0.25

# --- the elite --------------------------------------------------------------

## The design doc's "+100% HP" as a multiplier: an elite carries twice its base.
const ELITE_HP_MULTIPLIER: float = 2.0


# --- the curves -------------------------------------------------------------

## The HP an enemy on `biome_index` carries relative to its own base:
## `1.12 ** (biome_index - 1)`, so biome 1 is 1.0 and every step is the design
## doc's "about 12%". Clamped at the first biome, so an index of 0 or less reads
## as the baseline rather than as a fraction of it; the high end is not clamped,
## because the spec's formula is defined for any depth.
static func enemy_hp_mult(biome_index: int) -> float:
	return pow(BIOME_HP_MULTIPLIER, float(maxi(biome_index, FIRST_BIOME) - FIRST_BIOME))


## The damage an enemy on `biome_index` deals relative to its own base. The
## spec's sentence is "same for damage", so this is the HP curve and not a second
## one that could drift from it.
static func enemy_damage_mult(biome_index: int) -> float:
	return enemy_hp_mult(biome_index)


## The enemy budget `SpawnDirector` fills a combat room with on `floor_index`:
## `ENEMIES_PER_ROOM_BASE` plus a step per floor, capped. Monotonically
## non-decreasing, and clamped at both ends of the floor range so floor 0 reads
## as floor 1 and a floor past the design doc's depth reads as the last one.
static func enemies_per_room(floor_index: int) -> int:
	var depth: int = _clamped_floor(floor_index) - FIRST_FLOOR
	return mini(ENEMIES_PER_ROOM_BASE + floori(ENEMIES_PER_ROOM_PER_FLOOR * float(depth)), \
		ENEMIES_PER_ROOM_MAX)


## The chance a spawn slot on `floor_index` rolls an elite instead of a normal
## enemy: a base chance plus a step per floor, capped below 1.0. Monotonically
## non-decreasing, and clamped at both ends like `enemies_per_room`. A caller
## consuming Floor modifier "Double Elites" or Pit Pact multiplies this — those
## are floor-generation's rolls and are not folded in here.
static func elite_chance(floor_index: int) -> float:
	var depth: int = _clamped_floor(floor_index) - FIRST_FLOOR
	return minf(ELITE_CHANCE_BASE + ELITE_CHANCE_PER_FLOOR * float(depth), ELITE_CHANCE_MAX)


## An elite's max HP for `max_hp`: the design doc's "+100% HP", i.e. the base
## doubled. A pure function, so `enemies-ai`'s elite spawn (Dev A, W4-A1) can
## call it on the number it already computed and nothing about an elite's HP
## lives outside this class.
static func elite_hp(max_hp: float) -> float:
	return max_hp * ELITE_HP_MULTIPLIER


## The max HP an enemy of `base_hp` spawns with on `biome_index` in this
## session: the biome curve times the co-op multiplier. The co-op half is read
## from `NetworkManager.enemy_hp_multiplier()` — the module that owns player
## count — rather than from a second copy of the per-player constant here, so a
## change to the co-op rule is felt in one place (SPEC-networking owns it and its
## own test pins the table).
static func enemy_max_hp(base_hp: float, biome_index: int) -> float:
	return base_hp * enemy_hp_mult(biome_index) * NetworkManager.enemy_hp_multiplier()


## `floor_index` brought into the range both floor curves are defined over.
static func _clamped_floor(floor_index: int) -> int:
	return clampi(floor_index, FIRST_FLOOR, LAST_FLOOR)