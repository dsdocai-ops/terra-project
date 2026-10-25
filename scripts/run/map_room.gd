class_name MapRoom
extends RefCounted
## Map Room start floors (SPEC-run-economy "Map Room shortcuts"): a run may
## start at a rope the player has already reached (`map_room_deepest_rope`).
## Owned by run-economy (W5-B3). Pure functions, no node, no network.
##
## Ropes sit on floor 2 of each biome (2, 7, 12, 17, 22, 27) and in the boss
## arena after each biome boss (floors 5, 10, 15, 20, 25). A floor-2 rope starts
## the run on that floor; a boss-arena rope starts it on the next biome's floor 1
## (the boss is already dead). Floor 1 is always available.
##
## Ascension timing (design doc 4.2): starting past biome 1 means the Ascension
## is picked at run start; starting past biome 4 also starts at Tier 2
## (`classes-characters` reads `RunState.starts_tier_two`). Starting deeper gives
## no catch-up loot, which the design doc accepts as the risk-for-reward.

const FIRST_FLOOR: int = 1
## Past this biome the Ascension is picked at the start of the run.
const ASCENSION_PICK_AFTER_BIOME: int = 1
## Past this biome the run starts at Tier 2.
const TIER_TWO_AFTER_BIOME: int = 4


## Every rope floor in ascending order.
static func rope_floors() -> Array[int]:
	var ropes: Array[int] = []
	for biome: int in range(RunState.MIN_BIOME, RunState.MAX_BIOME + 1):
		var first: int = (biome - 1) * RunState.FLOORS_PER_BIOME + 1
		ropes.append(first + 1)
		if biome < RunState.MAX_BIOME:
			ropes.append(first + RunState.FLOORS_PER_BIOME - 1)
	return ropes


static func is_boss_arena_rope(rope_floor: int) -> bool:
	return rope_floor % RunState.FLOORS_PER_BIOME == 0


## The floor a run starts on when it starts at `rope_floor`; 0 for a floor that
## is not a rope.
static func start_floor_for_rope(rope_floor: int) -> int:
	if not rope_floors().has(rope_floor):
		return 0
	return rope_floor + 1 if is_boss_arena_rope(rope_floor) else rope_floor


## The floors a player whose deepest reached rope is `deepest_rope` may start on,
## ascending. A deepest rope of 0 (none reached) offers floor 1 only.
static func available_start_floors(deepest_rope: int) -> Array[int]:
	var floors: Array[int] = [FIRST_FLOOR]
	for rope: int in rope_floors():
		if rope <= deepest_rope:
			floors.append(start_floor_for_rope(rope))
	return floors


static func can_start_at(start_floor: int, deepest_rope: int) -> bool:
	return available_start_floors(deepest_rope).has(start_floor)


static func biome_of(floor_index: int) -> int:
	return (clampi(floor_index, RunState.MIN_FLOOR, RunState.MAX_FLOOR) - 1) / RunState.FLOORS_PER_BIOME + 1


static func ascension_picked_at_start(start_floor: int) -> bool:
	return biome_of(start_floor) > ASCENSION_PICK_AFTER_BIOME


static func starts_tier_two(start_floor: int) -> bool:
	return biome_of(start_floor) > TIER_TWO_AFTER_BIOME
