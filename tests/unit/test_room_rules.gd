extends GutTest
## Unit mirror of `FloorGenerator._assign_types` (W3-A1, G9b1): the room-type
## rules of SPEC-floor-generation step 4 — "Assign room types by rules (below).
## Start and Exit are the two most distant rooms by graph distance" — over the
## rules table's week-3 types (START, EXIT, COMBAT, ELITE_COMBAT, TREASURE,
## ROPE) and the priority the week-6 types drop in when a room-poor floor
## cannot carry them.

## Floors sampling every rules-table branch: below/at the elite gates, the
## rope floors, the lore floor, and deep past the second elite.
const FLOORS: Array[int] = [1, 2, 3, 5, 7, 10, 11, 12, 14, 19, 30]
## The priority the special types are claimed in (week-3 types first).
const PRIORITY: Array[int] = [
	FloorGenerator.RoomType.ROPE,
	FloorGenerator.RoomType.TREASURE,
	FloorGenerator.RoomType.ELITE_COMBAT,
	FloorGenerator.RoomType.LORE,
	FloorGenerator.RoomType.SHRINE,
	FloorGenerator.RoomType.SHOP,
	FloorGenerator.RoomType.REST,
	FloorGenerator.RoomType.ANVIL,
]

const SEEDS: Array[int] = [1, 7, 42, 99, 777, 4242, 31337, 99991, 123456, 20261020]


func _layout(run_seed: int, floor_index: int = 1) -> FloorLayout:
	return FloorGenerator.generate(run_seed, floor_index, BiomeData.for_index(1), [] as Array[int])


## Whether the rules table wants `type` on `floor_index` (count > 0).
func _wanted(type: int, floor_index: int, biome: BiomeData) -> bool:
	var in_biome: int = BiomeData.floor_in_biome(floor_index)
	if type == FloorGenerator.RoomType.ROPE:
		return in_biome == 2
	if type == FloorGenerator.RoomType.TREASURE or type == FloorGenerator.RoomType.SHRINE:
		return true
	if type == FloorGenerator.RoomType.ELITE_COMBAT:
		return floor_index >= 3
	if type == FloorGenerator.RoomType.LORE:
		return in_biome == biome.lore_floor
	if type == FloorGenerator.RoomType.SHOP:
		return in_biome >= 2 and in_biome <= 4
	if type == FloorGenerator.RoomType.REST:
		return in_biome >= 3 and in_biome <= 4
	if type == FloorGenerator.RoomType.ANVIL:
		return floor_index % 2 == 0 or floor_index % 5 == 4
	return false


func _expected_elites(floor_index: int) -> int:
	if floor_index < 3:
		return 0
	return 2 if floor_index >= 11 else 1


## A chain 0-1-...-count-1: the two ends are the unambiguous farthest pair.
func _path_adjacency(count: int) -> Array[PackedInt32Array]:
	var adjacency: Array[PackedInt32Array] = []
	for _index: int in count:
		adjacency.append(PackedInt32Array())
	for index: int in range(1, count):
		adjacency[index - 1].append(index)
		adjacency[index].append(index - 1)
	return adjacency


## A chain 0..6 with room 7 hung off room 3: after START (6) and EXIT (0) take
## the two ends, room 7 is the pool's only dead end.
func _unique_dead_end_adjacency() -> Array[PackedInt32Array]:
	var adjacency := _path_adjacency(7)
	adjacency.append(PackedInt32Array())  # room 7 hangs off room 3
	adjacency[3].append(7)
	adjacency[7].append(3)
	return adjacency


# --- step 4: Start and Exit are the two most distant rooms --------------------


func test_start_and_exit_take_a_path_graphs_two_ends() -> void:
	var biome: BiomeData = BiomeData.for_index(1)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var types: Array[int] = FloorGenerator._assign_types(rng, _path_adjacency(8), 1, biome)
	assert_eq(types[7], FloorGenerator.RoomType.START, "room 7, farthest from room 0, is Start")
	assert_eq(types[0], FloorGenerator.RoomType.EXIT, "room 0, farthest from room 7, is Exit")


func test_start_and_exit_are_the_most_distant_rooms_of_a_generated_floor() -> void:
	for run_seed: int in SEEDS:
		for floor_index: int in FLOORS:
			var layout: FloorLayout = _layout(run_seed, floor_index)
			var starts: int = layout.rooms_of_type(FloorGenerator.RoomType.START).size()
			var exits: int = layout.rooms_of_type(FloorGenerator.RoomType.EXIT).size()
			assert_eq(starts, 1, "seed %d floor %d: one Start" % [run_seed, floor_index])
			assert_eq(exits, 1, "seed %d floor %d: one Exit" % [run_seed, floor_index])
			var adjacency: Array[PackedInt32Array] = FloorGenerator._adjacency(
				layout.rooms.size(), layout.edges)
			var dist: Array[int] = FloorGenerator._bfs(adjacency, layout.start_room.index)
			assert_eq(layout.exit_room.index, FloorGenerator._farthest(dist),
				"seed %d floor %d: Exit is a farthest room from Start by graph distance"
				% [run_seed, floor_index])


# --- step 4: the rules table ---------------------------------------------------


func test_combat_is_the_default_and_at_least_two_stay_combat() -> void:
	for run_seed: int in SEEDS:
		for floor_index: int in FLOORS:
			var layout: FloorLayout = _layout(run_seed, floor_index)
			var combat: int = 0
			for room: RoomSpec in layout.rooms:
				if room.type == FloorGenerator.RoomType.COMBAT:
					combat += 1
				else:
					assert_true(PRIORITY.has(room.type) or room.type == FloorGenerator.RoomType.RUNE
						or room.type == FloorGenerator.RoomType.START or room.type == FloorGenerator.RoomType.EXIT,
						"seed %d floor %d: room %d carries a rules-table type (%d)"
						% [run_seed, floor_index, room.index, room.type])
			assert_gte(combat, FloorGenerator.MIN_COMBAT_ROOMS,
				"seed %d floor %d: %d combat rooms" % [run_seed, floor_index, combat])


func test_elite_combat_counts_follow_the_floor_index() -> void:
	for run_seed: int in SEEDS:
		for floor_index: int in FLOORS:
			var layout: FloorLayout = _layout(run_seed, floor_index)
			assert_eq(layout.rooms_of_type(FloorGenerator.RoomType.ELITE_COMBAT).size(),
				_expected_elites(floor_index),
				"seed %d floor %d: elite count" % [run_seed, floor_index])


func test_a_room_poor_floor_keeps_two_elites_and_drops_the_week_six_tail() -> void:
	# Direct on `_assign_types`: an 8-room chain at floor 12 (biome 1, so rope
	# wanted) has a budget of 4 for specials. The week-3 types (rope, treasure,
	# two elites) fill it exactly; the week-6 Shrine must be the type that
	# drops, not the second elite. Under the pre-G9b1 order (Shrine claimed
	# before the elites) this same graph carries only 1 elite.
	var biome: BiomeData = BiomeData.for_index(1)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var types: Array[int] = FloorGenerator._assign_types(rng, _path_adjacency(8), 12, biome)
	var elites: int = types.count(FloorGenerator.RoomType.ELITE_COMBAT)
	assert_eq(elites, 2, "both elites survive the budget")
	assert_eq(types.count(FloorGenerator.RoomType.SHRINE), 0, "the week-6 tail drops first")
	assert_eq(types.count(FloorGenerator.RoomType.ROPE), 1, "the rope still placed")


func test_no_elite_below_floor_three() -> void:
	for run_seed: int in SEEDS:
		for floor_index: int in [1, 2]:
			assert_eq(_layout(run_seed, floor_index).rooms_of_type(FloorGenerator.RoomType.ELITE_COMBAT).size(), 0,
				"seed %d floor %d: no elite before floor 3" % [run_seed, floor_index])


func test_treasure_is_one_per_floor_on_the_pools_dead_end() -> void:
	var biome: BiomeData = BiomeData.for_index(1)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var types: Array[int] = FloorGenerator._assign_types(rng, _unique_dead_end_adjacency(), 1, biome)
	assert_eq(types.count(FloorGenerator.RoomType.TREASURE), 1, "exactly one treasure room")
	var treasure: int = types.find(FloorGenerator.RoomType.TREASURE)
	assert_eq(_unique_dead_end_adjacency()[treasure].size(), 1,
		"the treasure sits on the pool's dead end (room 7)")


func test_rope_is_only_on_floor_two_of_a_biome() -> void:
	for run_seed: int in SEEDS:
		for floor_index: int in FLOORS:
			var ropes: int = _layout(run_seed, floor_index).rooms_of_type(FloorGenerator.RoomType.ROPE).size()
			var want: int = 1 if BiomeData.floor_in_biome(floor_index) == 2 else 0
			assert_eq(ropes, want, "seed %d floor %d: rope count" % [run_seed, floor_index])


func test_shrine_rides_as_far_as_the_floor_can_carry_it() -> void:
	# Shrine is "1 per floor" (a week-6 rule), but a room-poor floor that must
	# carry rope, treasure and two elites has no room left: the shrine drops
	# exactly when the specials ahead of it exhaust the budget. `budget >=
	# specials-ahead + 1` is that condition, so the count is 1 iff it fits.
	for run_seed: int in SEEDS:
		for floor_index: int in FLOORS:
			var layout: FloorLayout = _layout(run_seed, floor_index)
			var biome: BiomeData = BiomeData.for_index((floor_index - 1) / BiomeData.FLOORS_PER_BIOME + 1)
			var in_biome: int = BiomeData.floor_in_biome(floor_index)
			var ahead: int = 1  # treasure, always wanted
			if in_biome == 2:
				ahead += 1  # rope
			ahead += _expected_elites(floor_index)
			if in_biome == biome.lore_floor:
				ahead += 1  # lore claims the pool ahead of the shrine
			var budget: int = layout.rooms.size() - 2 - FloorGenerator.MIN_COMBAT_ROOMS
			var want: int = 1 if budget >= ahead + 1 else 0
			assert_eq(layout.rooms_of_type(FloorGenerator.RoomType.SHRINE).size(), want,
				"seed %d floor %d: shrine count" % [run_seed, floor_index])


func test_higher_priority_specials_drop_the_tail_first() -> void:
	# Once a wanted type is absent, no lower-priority wanted type may appear.
	for run_seed: int in SEEDS:
		for floor_index: int in FLOORS:
			var layout: FloorLayout = _layout(run_seed, floor_index)
			var biome: BiomeData = BiomeData.for_index((floor_index - 1) / BiomeData.FLOORS_PER_BIOME + 1)
			var dropped: Array[String] = []
			for type: int in PRIORITY:
				var present: bool = layout.rooms_of_type(type).size() > 0
				if not _wanted(type, floor_index, biome):
					continue
				if present:
					assert_true(dropped.is_empty(),
						"seed %d floor %d: %d placed after [%s] dropped"
						% [run_seed, floor_index, type, ", ".join(dropped)])
				else:
					dropped.append(str(type))


func test_the_assignment_is_deterministic_for_a_seed() -> void:
	var biome: BiomeData = BiomeData.for_index(1)
	for floor_index: int in FLOORS:
		var first_rng := RandomNumberGenerator.new()
		first_rng.seed = 4242
		var second_rng := RandomNumberGenerator.new()
		second_rng.seed = 4242
		var adjacency: Array[PackedInt32Array] = _path_adjacency(12)
		assert_eq(FloorGenerator._assign_types(first_rng, adjacency, floor_index, biome),
			FloorGenerator._assign_types(second_rng, adjacency, floor_index, biome),
			"floor %d: the same rng seed assigns the same types" % floor_index)
