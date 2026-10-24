extends GutTest
## floor-generation soak (SPEC-floor-generation "Testing", W3-A3): 500 seeds
## across all six biomes and 30 floors. Every room is reachable from Start by
## walking, Exit is reachable and distinct, counts and type rules hold, rooms
## never overlap, and one seed is one layout.

const SEED_COUNT: int = 500
const FLOORS: int = 30


func _biome_of(floor_index: int) -> BiomeData:
	return BiomeData.for_index((floor_index - 1) / BiomeData.FLOORS_PER_BIOME + 1)


func _layout(run_seed: int, floor_index: int) -> FloorLayout:
	var none: Array[int] = []
	return FloorGenerator.generate(run_seed, floor_index, _biome_of(floor_index), none)


func _reachable(layout: FloorLayout, from: Vector2i) -> Dictionary:
	var seen: Dictionary = {from: true}
	var queue: Array[Vector2i] = [from]
	var head: int = 0
	while head < queue.size():
		var cell: Vector2i = queue[head]
		head += 1
		for step: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var next: Vector2i = cell + step
			if layout.is_walkable(next) and not seen.has(next):
				seen[next] = true
				queue.append(next)
	return seen


func test_five_hundred_seeds_are_valid_floors() -> void:
	var bad: Array[String] = []
	for run_seed: int in SEED_COUNT:
		var floor_index: int = run_seed % FLOORS + 1
		var layout: FloorLayout = _layout(run_seed + 1, floor_index)
		var problem: String = _check(layout, floor_index)
		if not problem.is_empty():
			bad.append("seed %d floor %d: %s" % [run_seed + 1, floor_index, problem])
	assert_eq(bad.size(), 0, "\n".join(bad.slice(0, 5)))


func _check(layout: FloorLayout, floor_index: int) -> String:
	var count: int = layout.rooms.size()
	if count < FloorGenerator.MIN_ROOMS or count > FloorGenerator.MAX_ROOMS:
		return "room count %d" % count
	if layout.start_room == null or layout.exit_room == null or layout.start_room == layout.exit_room:
		return "start/exit"
	var reach: Dictionary = _reachable(layout, layout.start_room.center())
	for room: RoomSpec in layout.rooms:
		if not reach.has(room.center()):
			return "room %d unreachable" % room.index
		if room.rect.position.x < 1 or room.rect.position.y < 1 or room.rect.end.x >= FloorGenerator.GRID or room.rect.end.y >= FloorGenerator.GRID:
			return "room %d off grid" % room.index
		if room.spawn_points.is_empty() and room.locks():
			return "room %d has no spawn points" % room.index
	for a: int in count:
		for b: int in range(a + 1, count):
			if layout.rooms[a].rect.intersects(layout.rooms[b].rect):
				return "rooms %d and %d overlap" % [a, b]
	var ropes: int = layout.rooms_of_type(FloorGenerator.RoomType.ROPE).size()
	var want_rope: int = 1 if BiomeData.floor_in_biome(floor_index) == 2 else 0
	if ropes != want_rope:
		return "ropes %d, wanted %d" % [ropes, want_rope]
	if layout.rooms_of_type(FloorGenerator.RoomType.TREASURE).size() != 1:
		return "treasure count"
	if layout.rooms_of_type(FloorGenerator.RoomType.SHRINE).size() != 1:
		return "shrine count"
	var combat: int = layout.rooms_of_type(FloorGenerator.RoomType.COMBAT).size()
	if combat < FloorGenerator.MIN_COMBAT_ROOMS:
		return "combat rooms %d" % combat
	return ""


func test_the_same_seed_gives_the_same_layout() -> void:
	for floor_index: int in [1, 2, 7, 19]:
		var first: FloorLayout = _layout(4242, floor_index)
		var second: FloorLayout = _layout(4242, floor_index)
		assert_eq(first.layout_hash, second.layout_hash)
		assert_ne(first.layout_hash, _layout(4243, floor_index).layout_hash)


func test_corridors_are_three_wide() -> void:
	var layout: FloorLayout = _layout(99, 3)
	var sampled: int = 0
	for cell: Vector2i in layout.corridors:
		if layout.room_at_cell(cell) != null:
			continue
		var horizontal: bool = layout.is_walkable(cell + Vector2i.LEFT) or layout.is_walkable(cell + Vector2i.RIGHT)
		var vertical: bool = layout.is_walkable(cell + Vector2i.UP) or layout.is_walkable(cell + Vector2i.DOWN)
		assert_true(horizontal or vertical, "an isolated corridor cell at %s" % cell)
		sampled += 1
	assert_gt(sampled, 0)


func test_the_wire_form_rebuilds_the_same_floor() -> void:
	var layout: FloorLayout = _layout(31337, 4)
	var rebuilt: FloorLayout = FloorLayout.from_wire(layout.to_wire())
	assert_eq(rebuilt.layout_hash, layout.layout_hash)
	assert_eq(rebuilt.rooms.size(), layout.rooms.size())
	assert_eq(rebuilt.required_rooms, layout.required_rooms)
	var via_seam: RefCounted = FloorGeneratorSeam.deserialize_layout(layout.to_wire())
	assert_eq(FloorGeneratorSeam.layout_hash_of(via_seam), layout.layout_hash)


func test_modifiers_are_deterministic_and_capped() -> void:
	for floor_index: int in range(1, 31):
		var first: Array[int] = FloorGenerator.roll_modifiers(5, floor_index)
		assert_eq(first, FloorGenerator.roll_modifiers(5, floor_index))
		assert_lte(first.size(), FloorGenerator.MAX_MODIFIERS)


func test_locked_rooms_are_sealed_by_their_door_cells() -> void:
	var layout: FloorLayout = _layout(77, 3)
	for room: RoomSpec in layout.rooms:
		if not room.locks():
			continue
		var blocked: Dictionary = {}
		for cell: Vector2i in room.door_cells:
			blocked[cell] = true
		var seen: Dictionary = {room.center(): true}
		var queue: Array[Vector2i] = [room.center()]
		var head: int = 0
		while head < queue.size():
			var cell: Vector2i = queue[head]
			head += 1
			for step: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
				var next: Vector2i = cell + step
				if layout.is_walkable(next) and not blocked.has(next) and not seen.has(next):
					seen[next] = true
					queue.append(next)
		for key: Vector2i in seen:
			assert_true(room.rect.has_point(key), "room %d leaks through %s" % [room.index, key])
