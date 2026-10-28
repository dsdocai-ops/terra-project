extends GutTest
## Unit mirror of `scripts/generation/floor_generator.gd` (W3-A1, G9a1): the
## seeded room placement and its determinism. SPEC-floor-generation steps 1
## and 2: one RandomNumberGenerator seeded with `hash(run_seed, floor_index)`
## drives every roll, `room_count = rng.randi_range(8, 14)` rectangular rooms
## (default 9x7..17x13 tiles) by rejection sampling with a 2-tile gap, the
## whole floor retried up to 20 times when placement fails.
##
## The integration soak (`tests/integration/test_floor_generator.gd`) runs the
## 500 seeds; this file pins the placement contract itself.

const SEEDS: Array[int] = [1, 7, 42, 99, 777, 4242, 31337, 99991, 123456, 20261020]
const FLOORS: Array[int] = [1, 2, 7]
## The SPEC-floor-generation default room size range.
const SPEC_MIN := Vector2i(9, 7)
const SPEC_MAX := Vector2i(17, 13)


func _layout(run_seed: int, floor_index: int = 1) -> FloorLayout:
	return FloorGenerator.generate(run_seed, floor_index, BiomeData.for_index(1), [])


## Every way `b` fails to be `a`'s layout again (empty when identical).
func _differences(a: FloorLayout, b: FloorLayout) -> Array[String]:
	var problems: Array[String] = []
	if a.layout_hash != b.layout_hash:
		problems.append("layout_hash %d vs %d" % [a.layout_hash, b.layout_hash])
	if a.rooms.size() != b.rooms.size():
		problems.append("room count %d vs %d" % [a.rooms.size(), b.rooms.size()])
		return problems
	for index: int in a.rooms.size():
		if a.rooms[index].rect != b.rooms[index].rect:
			problems.append("room %d rect" % index)
		if a.rooms[index].type != b.rooms[index].type:
			problems.append("room %d type" % index)
	if a.corridors != b.corridors:
		problems.append("corridors")
	if a.edges != b.edges:
		problems.append("edges")
	if a.walkable.size() != b.walkable.size():
		problems.append("walkable count %d vs %d" % [a.walkable.size(), b.walkable.size()])
	else:
		for cell: Vector2i in a.walkable:
			if not b.walkable.has(cell):
				problems.append("walkable cell %s" % str(cell))
				break
	return problems


func test_the_same_seed_returns_the_same_layout() -> void:
	for run_seed: int in SEEDS:
		for floor_index: int in FLOORS:
			var first: FloorLayout = _layout(run_seed, floor_index)
			var second: FloorLayout = _layout(run_seed, floor_index)
			var problems: Array[String] = _differences(first, second)
			var message: String = "seed %d floor %d regenerated identically" % [run_seed, floor_index]
			if not problems.is_empty():
				message = "%s differs: %s" % [message, ", ".join(problems)]
			assert_true(problems.is_empty(), message)


func test_a_different_seed_gives_a_different_layout() -> void:
	for floor_index: int in FLOORS:
		var first: FloorLayout = _layout(4242, floor_index)
		for run_seed: int in [4243, 4244, 4245]:
			assert_ne(first.layout_hash, _layout(run_seed, floor_index).layout_hash,
				"seed %d floor %d differs from 4242" % [run_seed, floor_index])


func test_room_count_is_eight_to_fourteen() -> void:
	for run_seed: int in SEEDS:
		assert_between(_layout(run_seed).rooms.size(), FloorGenerator.MIN_ROOMS,
			FloorGenerator.MAX_ROOMS, "seed %d room count" % run_seed)


func test_rooms_are_nine_by_seven_to_seventeen_by_thirteen() -> void:
	for run_seed: int in SEEDS:
		for room: RoomSpec in _layout(run_seed).rooms:
			assert_gte(room.rect.size.x, SPEC_MIN.x, "seed %d room %d width" % [run_seed, room.index])
			assert_gte(room.rect.size.y, SPEC_MIN.y, "seed %d room %d height" % [run_seed, room.index])
			assert_lte(room.rect.size.x, SPEC_MAX.x, "seed %d room %d width" % [run_seed, room.index])
			assert_lte(room.rect.size.y, SPEC_MAX.y, "seed %d room %d height" % [run_seed, room.index])


func test_rejection_sampling_keeps_the_room_gap() -> void:
	for run_seed: int in SEEDS:
		var rooms: Array[RoomSpec] = _layout(run_seed).rooms
		for a: int in rooms.size():
			for b: int in range(a + 1, rooms.size()):
				var grown: Rect2i = rooms[a].rect.grow(FloorGenerator.ROOM_GAP)
				assert_false(grown.intersects(rooms[b].rect),
					"seed %d rooms %d/%d closer than the %d-tile gap" % [run_seed, a, b, FloorGenerator.ROOM_GAP])


func test_later_placement_attempts_shrink_the_largest_room() -> void:
	# The whole-floor retry: a crowded roll re-places with a smaller maximum
	# (SPEC step 2's "retry whole floor up to 20 times"), so the last attempt's
	# rooms all fit the shrunk bounds.
	var biome: BiomeData = BiomeData.for_index(1)
	var early_rng := RandomNumberGenerator.new()
	early_rng.seed = 123456
	var early: Array[Rect2i] = FloorGenerator._place_rooms(early_rng, biome, 0)
	var late_rng := RandomNumberGenerator.new()
	late_rng.seed = 123456
	var late_attempt: int = FloorGenerator.MAX_FLOOR_ATTEMPTS - 1
	var late: Array[Rect2i] = FloorGenerator._place_rooms(late_rng, biome, late_attempt)
	assert_gt(early.size(), 0, "the first attempt places rooms")
	assert_gt(late.size(), 0, "a shrunk attempt still places rooms")
	var shrink: int = late_attempt / 4
	var max_w: int = maxi(biome.room_size_max.x - shrink * 2, biome.room_size_min.x)
	var max_h: int = maxi(biome.room_size_max.y - shrink * 2, biome.room_size_min.y)
	for rect: Rect2i in late:
		assert_lte(rect.size.x, max_w, "late attempt width %d vs max %d" % [rect.size.x, max_w])
		assert_lte(rect.size.y, max_h, "late attempt height %d vs max %d" % [rect.size.y, max_h])
	for rect: Rect2i in early:
		assert_lte(rect.size.x, biome.room_size_max.x, "early attempt stays in the biome range")
		assert_lte(rect.size.y, biome.room_size_max.y, "early attempt stays in the biome range")


func test_the_fallback_rooms_are_a_valid_floor_skeleton() -> void:
	var rects: Array[Rect2i] = FloorGenerator._fallback_rooms()
	assert_eq(rects.size(), 9, "the 3x3 last resort")
	for rect: Rect2i in rects:
		assert_gte(rect.size.x, SPEC_MIN.x)
		assert_gte(rect.size.y, SPEC_MIN.y)
		assert_lte(rect.size.x, SPEC_MAX.x)
		assert_lte(rect.size.y, SPEC_MAX.y)
		assert_gte(rect.position.x, FloorGenerator.EDGE_MARGIN)
		assert_gte(rect.position.y, FloorGenerator.EDGE_MARGIN)
		assert_lte(rect.end.x, FloorGenerator.GRID - FloorGenerator.EDGE_MARGIN)
		assert_lte(rect.end.y, FloorGenerator.GRID - FloorGenerator.EDGE_MARGIN)
	for a: int in rects.size():
		for b: int in range(a + 1, rects.size()):
			assert_false(rects[a].grow(FloorGenerator.ROOM_GAP).intersects(rects[b]),
				"fallback rooms %d/%d too close" % [a, b])


func test_every_random_call_goes_through_the_seeded_rng() -> void:
	# SPEC step 1: "All randomness in generation uses this RNG and nothing else
	# (no randi(), no shuffle() without the RNG)." Reads the generator source
	# and flags any randi/randf/shuffle call the seeded `rng.` does not prefix.
	var file := FileAccess.open("res://scripts/generation/floor_generator.gd", FileAccess.READ)
	assert_not_null(file, "the generator source is readable")
	if file == null:
		return
	var regex := RegEx.new()
	regex.compile("(randi|randf|shuffle)")
	var offenders: Array[String] = []
	var calls: int = 0
	var lines: PackedStringArray = file.get_as_text().split("\n")
	for index: int in lines.size():
		var code: String = lines[index]
		var comment: int = code.find("#")
		if comment >= 0:
			code = code.substr(0, comment)
		for match: RegExMatch in regex.search_all(code):
			calls += 1
			if match.get_start() < 4 or code.substr(match.get_start() - 4, 4) != "rng.":
				offenders.append("line %d: %s" % [index + 1, code.strip_edges()])
	assert_gt(calls, 0, "the generator rolls the seeded RNG")
	assert_eq(offenders.size(), 0, "\n".join(offenders))
