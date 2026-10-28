extends GutTest
## The 500-seed floor soak (SPEC-floor-generation "Testing", design doc section
## 23; W3-A3). Since Dev A's generator landed it runs the real
## `FloorGenerator.generate()` — the layout the game actually plays — over 500
## seeds, and asserts what the co-op hash assertion and the room loop depend on:
##   * the same inputs always yield the same `layout_hash` and the same rooms,
##   * 500 different seeds do not collapse onto one hash (no constant), and no
##     two neighbouring seeds share a hash,
##   * a layout rebuilt from its own wire form (`to_wire()` -> `from_wire()`)
##     keeps the identical `layout_hash`, which is what the mismatch fallback
##     hands a diverged peer,
##   * every room rect fits inside the 96x96 tile grid at the spec room sizes,
##   * `room_count` stays inside the spec's 8..14 range,
##   * a flood fill from the Start room reaches every room and the Exit,
##   * exactly one ROPE on each biome's floor 2 and none elsewhere,
##   * no two rooms overlap, and
##   * every corridor's centre-line path is walkable 3 tiles wide.
## It also runs the negative control the run's rules ask for: changing exactly
## one input (floor_index, biome_id, or a modifier) must move the hash, so the
## equality assertions above cannot pass vacuously.
## The seam guard stays as the last test: `FloorGeneratorSeam.generate()` — the
## path the game's floor sync takes — must return the real generator's layout.
##
## Owned by networking (W3-B3c's determinism proof) over Dev A's generator
## (W3-A3). The lane-B `FloorLayoutPlaceholder` era is gone: the seam falls back
## to it only when `scripts/generation/floor_generator.gd` is missing, and the
## guard test would catch that.
##
## Sync: none — nothing here talks to a peer. It proves the determinism the
## broadcast relies on: one seed, one floor, in any process.
##
## No autoload state is read or written (`BiomeData.for_index()` is a pure
## static), so nothing can leak into another test file; the one seam test reads
## `GameState` only through `biome_for_index()`, which is a pure lookup.

## The spec's soak size. 500 seeds in a row (SPEC-floor-generation "Testing",
## design doc section 23).
const SOAK_SEEDS: int = 500
## A fixed base so a failing seed can be reproduced by hand from the log line.
const SOAK_BASE_SEED: int = 20261020
## The spec's numbers, asserted against the implementation's own constants so a
## drift in either one fails this file rather than silently widening the soak.
const SPEC_MIN_ROOMS: int = 8
const SPEC_MAX_ROOMS: int = 14
const SPEC_GRID_TILES: int = 96
const SPEC_MIN_ROOM_W: int = 9
const SPEC_MAX_ROOM_W: int = 17
const SPEC_MIN_ROOM_H: int = 7
const SPEC_MAX_ROOM_H: int = 13
## Floors 1..30 across the six biomes, so one loop of the soak touches every
## biome the spec names without multiplying the iteration count.
const MAX_FLOOR: int = 30
const FLOORS_PER_BIOME: int = 5


## A shared empty modifier list. `generate()` copies it, so one instance is
## safe to hand to every call.
var _no_modifiers: Array[int] = []


## The run seed of soak iteration `index`, so every iteration is a different
## seed and any failure names a reproducible one.
func _run_seed(index: int) -> int:
	return SOAK_BASE_SEED + index


## The floor soak iteration `index` covers: 1..30, wrapping, so the loop walks
## every floor index the run can reach.
func _floor_of(index: int) -> int:
	return (index % MAX_FLOOR) + 1


## The biome a floor index belongs to (SPEC-run-economy: `(floor - 1) / 5 + 1`),
## in 1..6.
func _biome_of(floor_index: int) -> int:
	return ((floor_index - 1) / FLOORS_PER_BIOME) + 1


## The real generator's layout for one soak floor.
func _layout(run_seed: int, floor_index: int) -> FloorLayout:
	var biome: BiomeData = BiomeData.for_index(_biome_of(floor_index))
	return FloorGenerator.generate(run_seed, floor_index, biome, _no_modifiers)


## The problem string for one layout's room shapes: a rect off the grid or
## outside the spec's 9x7..17x13 room sizes, else "".
func _bounds_problem(layout: FloorLayout, run_seed: int, floor_index: int) -> String:
	for room: RoomSpec in layout.rooms:
		var rect: Rect2i = room.rect
		if rect.position.x < 1 or rect.position.y < 1:
			return "seed %d floor %d: room %s starts before the grid" % [run_seed, floor_index, rect]
		if rect.end.x >= SPEC_GRID_TILES or rect.end.y >= SPEC_GRID_TILES:
			return "seed %d floor %d: room %s runs past the %d-tile grid" % [run_seed, floor_index, rect, SPEC_GRID_TILES]
		if rect.size.x < SPEC_MIN_ROOM_W or rect.size.x > SPEC_MAX_ROOM_W:
			return "seed %d floor %d: room %s width outside the spec range" % [run_seed, floor_index, rect]
		if rect.size.y < SPEC_MIN_ROOM_H or rect.size.y > SPEC_MAX_ROOM_H:
			return "seed %d floor %d: room %s height outside the spec range" % [run_seed, floor_index, rect]
	return ""


## The problem string for one layout's room graph: a Start or Exit missing, the
## Exit not reachable by flood fill from Start, or a room whose centre the fill
## cannot reach, else "".
func _reach_problem(layout: FloorLayout, run_seed: int, floor_index: int) -> String:
	if layout.start_room == null or layout.exit_room == null:
		return "seed %d floor %d: no Start or no Exit" % [run_seed, floor_index]
	if layout.start_room == layout.exit_room:
		return "seed %d floor %d: Start and Exit are the same room" % [run_seed, floor_index]
	var seen: Dictionary[Vector2i, bool] = _flood_fill(layout, layout.start_room.center())
	for room: RoomSpec in layout.rooms:
		if not seen.has(room.center()):
			return "seed %d floor %d: room %d unreachable by flood fill" % [run_seed, floor_index, room.index]
	if not seen.has(layout.exit_room.center()):
		return "seed %d floor %d: Exit unreachable by flood fill" % [run_seed, floor_index]
	return ""


## Flood fill over the layout's walkable cells from `from`.
func _flood_fill(layout: FloorLayout, from: Vector2i) -> Dictionary[Vector2i, bool]:
	var seen: Dictionary[Vector2i, bool] = {from: true}
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


## The problem string for one layout's types and geometry: the ROPE count (one
## on each biome's floor 2, none elsewhere) or an overlapping room pair, else "".
func _rope_and_overlap_problem(layout: FloorLayout, run_seed: int, floor_index: int) -> String:
	var in_biome: int = BiomeData.floor_in_biome(floor_index)
	var want_rope: int = 1 if in_biome == 2 else 0
	var ropes: int = layout.rooms_of_type(FloorGenerator.RoomType.ROPE).size()
	if ropes != want_rope:
		return "seed %d floor %d: %d ropes, wanted %d" % [run_seed, floor_index, ropes, want_rope]
	var count: int = layout.rooms.size()
	for a: int in count:
		for b: int in range(a + 1, count):
			if layout.rooms[a].rect.intersects(layout.rooms[b].rect):
				return "seed %d floor %d: rooms %d and %d overlap" % [run_seed, floor_index, a, b]
	return ""


## The problem string for one layout's corridor width: an edge whose centre-line
## path — the L the carve walks, straight band then perpendicular band — is
## missing any cell of its 3-tile slice, else "". Rooms make their own cells
## walkable, so the check passes wherever the path crosses a room.
func _corridor_problem(layout: FloorLayout) -> String:
	for edge: Vector2i in layout.edges:
		var from: Vector2i = layout.rooms[edge.x].center()
		var to: Vector2i = layout.rooms[edge.y].center()
		if to.x != from.x:
			var step_x: int = 1 if to.x >= from.x else -1
			var x: int = from.x
			while true:
				var missing: Vector2i = _unwalkable_in_slice(layout, Vector2i(x, from.y), true)
				if missing.x >= 0:
					return "edge %d-%d: corridor cell %s not walkable" % [edge.x, edge.y, missing]
				if x == to.x:
					break
				x += step_x
		if to.y != from.y:
			var step_y: int = 1 if to.y >= from.y else -1
			var y: int = from.y
			while true:
				var missing: Vector2i = _unwalkable_in_slice(layout, Vector2i(to.x, y), false)
				if missing.x >= 0:
					return "edge %d-%d: corridor cell %s not walkable" % [edge.x, edge.y, missing]
				if y == to.y:
					break
				y += step_y
	return ""


## The first unwalkable cell of the 3-tile slice across `centre` (perpendicular
## to the walk direction), or `(-1, -1)` when the whole slice is walkable.
func _unwalkable_in_slice(layout: FloorLayout, centre: Vector2i, horizontal: bool) -> Vector2i:
	for offset: int in [-1, 0, 1]:
		var cell: Vector2i = centre + (Vector2i(0, offset) if horizontal else Vector2i(offset, 0))
		if not layout.is_walkable(cell):
			return cell
	return Vector2i(-1, -1)


func test_the_soak_covers_the_specs_floor_shape() -> void:
	assert_eq(FloorGenerator.MIN_ROOMS, SPEC_MIN_ROOMS, "spec: room_count = rng.randi_range(8, 14)")
	assert_eq(FloorGenerator.MAX_ROOMS, SPEC_MAX_ROOMS, "spec: room_count = rng.randi_range(8, 14)")
	assert_eq(FloorGenerator.GRID, SPEC_GRID_TILES, "spec: grid of 96x96 tiles")
	for biome_index: int in range(1, 7):
		var biome: BiomeData = BiomeData.for_index(biome_index)
		assert_eq(biome.room_size_min, Vector2i(SPEC_MIN_ROOM_W, SPEC_MIN_ROOM_H),
			"biome %d: spec rooms 9x7 to 17x13 tiles (min)" % biome_index)
		assert_eq(biome.room_size_max, Vector2i(SPEC_MAX_ROOM_W, SPEC_MAX_ROOM_H),
			"biome %d: spec rooms 9x7 to 17x13 tiles (max)" % biome_index)
	assert_gte(SOAK_SEEDS, 500, "the soak covers at least 500 seeds")
	assert_eq(_biome_of(1), 1, "floor 1 is biome 1")
	assert_eq(_biome_of(MAX_FLOOR), 6, "floor 30 is biome 6")


func test_500_seeds_rebuild_the_same_layout() -> void:
	var checked: int = 0
	for index: int in SOAK_SEEDS:
		var run_seed: int = _run_seed(index)
		var first: FloorLayout = _layout(run_seed, 1)
		var again: FloorLayout = _layout(run_seed, 1)
		assert_eq(first.layout_hash, again.layout_hash, "seed %d: same inputs, same hash" % run_seed)
		assert_eq(first.rooms.size(), again.rooms.size(), "seed %d: same inputs, same room count" % run_seed)
		for room_index: int in first.rooms.size():
			assert_eq(first.rooms[room_index].rect, again.rooms[room_index].rect,
				"seed %d: room %d same rect" % [run_seed, room_index])
			assert_eq(first.rooms[room_index].type, again.rooms[room_index].type,
				"seed %d: room %d same type" % [run_seed, room_index])
		assert_eq(first.corridors, again.corridors, "seed %d: same corridor cells" % run_seed)
		assert_eq(first.seed, run_seed, "seed %d: the layout carries its seed" % run_seed)
		checked += 1
	assert_eq(checked, SOAK_SEEDS, "the soak rebuilt every seed")
	print("[soak] floor determinism: %d seeds x 1 floor rebuilt identically" % checked)


func test_500_seeds_do_not_collapse_onto_one_hash() -> void:
	var hashes: Dictionary[int, bool] = {}
	var neighbouring_matches: int = 0
	var previous: int = 0
	var first: bool = true
	for index: int in SOAK_SEEDS:
		var run_seed: int = _run_seed(index)
		var layout: FloorLayout = _layout(run_seed, 1)
		assert_ne(layout.layout_hash, 0, "seed %d produced a real hash" % run_seed)
		hashes[layout.layout_hash] = true
		if not first and previous == layout.layout_hash:
			neighbouring_matches += 1
		previous = layout.layout_hash
		first = false
	assert_eq(hashes.size(), SOAK_SEEDS, "500 different seeds give 500 different hashes")
	assert_eq(neighbouring_matches, 0, "neighbouring seeds never share a hash")
	print("[soak] floor hashes: %d seeds, %d distinct hashes, 0 neighbouring collisions" % [SOAK_SEEDS, hashes.size()])


func test_500_seeds_survive_the_wire_round_trip() -> void:
	var checked: int = 0
	for index: int in SOAK_SEEDS:
		var run_seed: int = _run_seed(index)
		var floor_index: int = _floor_of(index)
		var layout: FloorLayout = _layout(run_seed, floor_index)
		var rebuilt: FloorLayout = FloorLayout.from_wire(layout.to_wire())
		assert_eq(rebuilt.layout_hash, layout.layout_hash,
			"seed %d floor %d: the hash travels with the content" % [run_seed, floor_index])
		assert_eq(rebuilt.rooms.size(), layout.rooms.size(),
			"seed %d floor %d: the room count survives the wire" % [run_seed, floor_index])
		assert_eq(rebuilt.corridors, layout.corridors,
			"seed %d floor %d: the corridor cells survive the wire" % [run_seed, floor_index])
		assert_eq(rebuilt.seed, run_seed, "seed %d floor %d: the seed survives" % [run_seed, floor_index])
		assert_eq(rebuilt.floor_index, floor_index, "seed %d: the floor index survives" % run_seed)
		assert_eq(rebuilt.biome_id, _biome_of(floor_index), "seed %d: the biome id survives" % run_seed)
		checked += 1
	assert_eq(checked, SOAK_SEEDS, "the round trip covered every seed")
	print("[soak] wire round-trip: %d layouts rebuilt from to_wire() with identical hashes" % checked)


func test_every_room_fits_inside_the_grid_over_500_seeds() -> void:
	var rooms_checked: int = 0
	for index: int in SOAK_SEEDS:
		var run_seed: int = _run_seed(index)
		var floor_index: int = _floor_of(index)
		var layout: FloorLayout = _layout(run_seed, floor_index)
		var problem: String = _bounds_problem(layout, run_seed, floor_index)
		assert_eq(problem, "", "seed %d floor %d room bounds" % [run_seed, floor_index])
		rooms_checked += layout.rooms.size()
	assert_gte(rooms_checked, SOAK_SEEDS * SPEC_MIN_ROOMS, "every seed placed at least 8 rooms")
	print("[soak] grid bounds: %d room rects across %d seeds, all inside %dx%d tiles at the spec sizes" % [
		rooms_checked, SOAK_SEEDS, SPEC_GRID_TILES, SPEC_GRID_TILES])


func test_room_count_stays_in_the_spec_range_over_500_seeds() -> void:
	var checked: int = 0
	var smallest: int = SPEC_MAX_ROOMS
	var largest: int = SPEC_MIN_ROOMS
	for index: int in SOAK_SEEDS:
		var run_seed: int = _run_seed(index)
		var floor_index: int = _floor_of(index)
		var layout: FloorLayout = _layout(run_seed, floor_index)
		assert_between(layout.rooms.size(), SPEC_MIN_ROOMS, SPEC_MAX_ROOMS,
			"seed %d floor %d: room count" % [run_seed, floor_index])
		smallest = mini(smallest, layout.rooms.size())
		largest = maxi(largest, layout.rooms.size())
		checked += 1
	assert_eq(checked, SOAK_SEEDS, "the range check covered every seed")
	print("[soak] room counts: %d seeds, %d..%d rooms per floor (spec range %d..%d)" % [
		checked, smallest, largest, SPEC_MIN_ROOMS, SPEC_MAX_ROOMS])


func test_negative_control_one_changed_input_moves_the_hash() -> void:
	var checked: int = 0
	for index: int in SOAK_SEEDS:
		var run_seed: int = _run_seed(index)
		var base: FloorLayout = _layout(run_seed, 2)
		var other_floor: FloorLayout = _layout(run_seed, 3)
		var other_biome: FloorLayout = FloorGenerator.generate(run_seed, 2, BiomeData.for_index(2), _no_modifiers)
		var with_modifier: FloorLayout = FloorGenerator.generate(run_seed, 2, BiomeData.for_index(1), [1] as Array[int])
		assert_ne(base.layout_hash, other_floor.layout_hash, "seed %d: floor_index 2 vs 3" % run_seed)
		assert_ne(base.layout_hash, other_biome.layout_hash, "seed %d: biome_id 1 vs 2" % run_seed)
		assert_ne(base.layout_hash, with_modifier.layout_hash, "seed %d: no modifier vs modifier 1" % run_seed)
		checked += 1
	assert_eq(checked, SOAK_SEEDS, "the negative control covered every seed")
	print("[soak] negative control: %d seeds, every single-input change moved the hash" % checked)


func test_500_seeds_are_reachable_by_flood_fill_and_the_exit_is_reachable() -> void:
	var checked: int = 0
	for index: int in SOAK_SEEDS:
		var run_seed: int = _run_seed(index)
		var floor_index: int = _floor_of(index)
		var layout: FloorLayout = _layout(run_seed, floor_index)
		assert_eq(_reach_problem(layout, run_seed, floor_index), "",
			"seed %d floor %d reachability" % [run_seed, floor_index])
		checked += 1
	assert_eq(checked, SOAK_SEEDS, "the reachability check covered every seed")
	print("[soak] reachability: %d floors, every room and the Exit reached by flood fill from Start" % checked)


func test_500_seeds_carry_one_rope_on_floor_2_and_never_overlap() -> void:
	var checked: int = 0
	for index: int in SOAK_SEEDS:
		var run_seed: int = _run_seed(index)
		var floor_index: int = _floor_of(index)
		var layout: FloorLayout = _layout(run_seed, floor_index)
		assert_eq(_rope_and_overlap_problem(layout, run_seed, floor_index), "",
			"seed %d floor %d rope and overlap rules" % [run_seed, floor_index])
		checked += 1
	assert_eq(checked, SOAK_SEEDS, "the rope and overlap check covered every seed")
	print("[soak] rope and overlaps: %d floors, one rope on each biome's floor 2, no overlapping rooms" % checked)


func test_500_seeds_carve_three_wide_corridors() -> void:
	var checked: int = 0
	for index: int in SOAK_SEEDS:
		var run_seed: int = _run_seed(index)
		var floor_index: int = _floor_of(index)
		var layout: FloorLayout = _layout(run_seed, floor_index)
		assert_eq(_corridor_problem(layout), "",
			"seed %d floor %d: corridor width" % [run_seed, floor_index])
		checked += 1
	assert_eq(checked, SOAK_SEEDS, "the corridor-width check covered every seed")
	print("[soak] corridor width: %d floors, every edge's centre path walkable 3 tiles wide" % checked)


func test_the_game_generation_path_soaks_the_same_layout() -> void:
	var run_seed: int = SOAK_BASE_SEED
	var layout: RefCounted = FloorGeneratorSeam.generate(run_seed, 1, 1, _no_modifiers)
	assert_not_null(layout, "the generation seam always produces a layout")
	# The seam guard: Dev A's `FloorGenerator` is present, so the seam — the path
	# the game's floor sync takes — must generate its layout, not a stand-in.
	assert_ne(FloorGeneratorSeam.layout_hash_of(layout), 0,
		"Dev A's FloorGenerator is present, so the seam must generate its layout")
	assert_eq(FloorGeneratorSeam.source_of(layout), FloorLayout.SOURCE,
		"the seam's layout is the real floor-generation layout")
	assert_eq(FloorGeneratorSeam.layout_hash_of(layout), _layout(run_seed, 1).layout_hash,
		"and it is the same layout the soak above rebuilt from FloorGenerator.generate()")
