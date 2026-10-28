extends GutTest
## Unit mirror of `scripts/generation/floor_generator.gd` (W3-A1): G9a1 pinned
## the seeded room placement and its determinism; G9a2 pins the graph and the
## carving. SPEC-floor-generation steps 1 to 3: one RandomNumberGenerator
## seeded with `hash(run_seed, floor_index)` drives every roll,
## `room_count = rng.randi_range(8, 14)` rectangular rooms (default 9x7..17x13
## tiles) by rejection sampling with a 2-tile gap, the whole floor retried up
## to 20 times when placement fails; rooms are joined by a minimum spanning
## tree on room centres plus 1..3 extra loop edges, carved as L-shaped
## corridors 3 tiles wide.
##
## The integration soak (`tests/integration/test_floor_generator.gd`) runs the
## 500 seeds; this file pins the placement, graph and corridor contract.

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


# --- G9a2: the MST plus loops, and the L corridors (SPEC step 3) ---------------


## Kraskal's minimum spanning tree total centre-distance weight over `rects` —
## a second algorithm the Prim sweep in `_connect` is checked against (the MST
## weight is unique even where several trees tie).
func _kraskal_weight(rects: Array[Rect2i]) -> int:
	var all_pairs: Array[Vector2i] = []
	for a: int in rects.size():
		for b: int in range(a + 1, rects.size()):
			all_pairs.append(Vector2i(a, b))
	all_pairs.sort_custom(func(p: Vector2i, q: Vector2i) -> bool:
		return FloorGenerator._dist2(rects[p.x], rects[p.y]) < FloorGenerator._dist2(rects[q.x], rects[q.y]))
	var parent: Array[int] = []
	parent.resize(rects.size())
	for index: int in rects.size():
		parent[index] = index
	var weight: int = 0
	var joined: int = 0
	for pair: Vector2i in all_pairs:
		var root_a: int = pair.x
		while parent[root_a] != root_a:
			root_a = parent[root_a]
		var root_b: int = pair.y
		while parent[root_b] != root_b:
			root_b = parent[root_b]
		if root_a == root_b:
			continue
		parent[root_a] = root_b
		weight += FloorGenerator._dist2(rects[pair.x], rects[pair.y])
		joined += 1
		if joined == rects.size() - 1:
			break
	return weight


## Every room reachable from room 0 through `edges` (BFS over the room graph).
func _all_reached(count: int, edges: Array[Vector2i]) -> bool:
	var adjacency: Array[PackedInt32Array] = FloorGenerator._adjacency(count, edges)
	var seen: Array[bool] = []
	seen.resize(count)
	seen[0] = true
	var queue: Array[int] = [0]
	var head: int = 0
	while head < queue.size():
		var current: int = queue[head]
		head += 1
		for next: int in adjacency[current]:
			if not seen[next]:
				seen[next] = true
				queue.append(next)
	for reached: bool in seen:
		if not reached:
			return false
	return true


func test_the_spanning_tree_joins_every_room_at_minimum_weight() -> void:
	# SPEC step 3, first half: "Connect rooms with a minimum spanning tree on
	# room centers". `_connect` appends the tree edges first, so the first
	# count-1 edges are the tree: count-1 of them, touching every room,
	# reachable as one component, at the Kraskal-optimal weight.
	for run_seed: int in SEEDS:
		var rects: Array[Rect2i] = []
		for room: RoomSpec in _layout(run_seed).rooms:
			rects.append(room.rect)
		var rng := RandomNumberGenerator.new()
		rng.seed = run_seed
		var edges: Array[Vector2i] = FloorGenerator._connect(rng, rects)
		var count: int = rects.size()
		var tree: Array[Vector2i] = edges.slice(0, count - 1)
		assert_eq(tree.size(), count - 1, "seed %d: the tree part is count-1 edges" % run_seed)
		assert_true(_all_reached(count, tree), "seed %d: the tree alone reaches every room" % run_seed)
		var weight: int = 0
		for edge: Vector2i in tree:
			weight += FloorGenerator._dist2(rects[edge.x], rects[edge.y])
		assert_eq(weight, _kraskal_weight(rects), "seed %d: the tree is a minimum spanning tree" % run_seed)


func test_loops_add_one_to_three_edges_between_unjoined_rooms() -> void:
	# SPEC step 3: "then add loops = rng.randi_range(1, 3) extra edges between
	# non-adjacent rooms". The tail beyond the count-1 tree edges is the loops:
	# 1..3 of them, each a pair the tree does not already join, none repeated.
	for run_seed: int in SEEDS:
		var rects: Array[Rect2i] = []
		for room: RoomSpec in _layout(run_seed).rooms:
			rects.append(room.rect)
		var rng := RandomNumberGenerator.new()
		rng.seed = run_seed
		var edges: Array[Vector2i] = FloorGenerator._connect(rng, rects)
		var count: int = rects.size()
		var tree_set: Dictionary[Vector2i, bool] = {}
		for index: int in count - 1:
			tree_set[edges[index]] = true
		var loops: Array[Vector2i] = edges.slice(count - 1)
		assert_between(loops.size(), 1, 3, "seed %d: %d loop edges" % [run_seed, loops.size()])
		var loop_set: Dictionary[Vector2i, bool] = {}
		for edge: Vector2i in loops:
			assert_false(tree_set.has(edge), "seed %d: loop %s duplicates a tree edge" % [run_seed, str(edge)])
			assert_false(loop_set.has(edge), "seed %d: loop %s repeats" % [run_seed, str(edge)])
			loop_set[edge] = true
		# The full graph (tree plus loops) still reaches every room.
		assert_true(_all_reached(count, edges), "seed %d: every room joined" % run_seed)


## The exact cells an L corridor between `from` and `to` must carve: the 3-wide
## horizontal band along `from.y` to `to.x`, the 3-wide vertical band down
## `to.x` to `to.y`, and the filled 3x3 corner at the turn. A straight edge
## (centres sharing an x or a y) has no turn: its band alone, no overshoot.
func _expected_l_cells(from: Vector2i, to: Vector2i) -> Dictionary[Vector2i, bool]:
	var expected: Dictionary[Vector2i, bool] = {}
	if to.x != from.x:
		var step_x: int = 1 if to.x >= from.x else -1
		var x: int = from.x
		while true:
			for dy: int in range(-1, 2):
				expected[Vector2i(x, from.y + dy)] = true
			if x == to.x:
				break
			x += step_x
	if to.y != from.y:
		var step_y: int = 1 if to.y >= from.y else -1
		var y: int = from.y
		while true:
			for dx: int in range(-1, 2):
				expected[Vector2i(to.x + dx, y)] = true
			if y == to.y:
				break
			y += step_y
	if to.x != from.x and to.y != from.y:
		# The filled 3x3 corner at the turn. Only a real turn has one: a
		# straight edge (one axis shared) carves its band alone, so the
		# corner must not add 3 cells past the band at either centre.
		for dx: int in range(-1, 2):
			for dy: int in range(-1, 2):
				expected[Vector2i(to.x + dx, from.y + dy)] = true
	return expected


func _assert_carve_matches(rects: Array[Rect2i], from: Vector2i, to: Vector2i, label: String) -> void:
	var carved: Array[Vector2i] = FloorGenerator._carve_corridors(rects, [Vector2i(0, 1)])
	var expected: Dictionary[Vector2i, bool] = _expected_l_cells(from, to)
	assert_eq(carved.size(), expected.size(), "%s: exactly the L bands, no duplicates" % label)
	for cell: Vector2i in carved:
		assert_true(expected.has(cell), "%s: unexpected corridor cell %s" % [label, str(cell)])


func test_l_corridors_carve_the_exact_three_wide_shape() -> void:
	# SPEC step 3: "Corridors are L-shaped, 3 tiles wide, carved on the grid."
	# Room 0's centre (13, 13) to room 1's (43, 33): right, then down.
	_assert_carve_matches([Rect2i(10, 10, 6, 6), Rect2i(40, 30, 6, 6)], Vector2i(13, 13), Vector2i(43, 33), "right-down")


func test_l_corridors_run_the_other_two_directions_too() -> void:
	# The same carve run left (to.x < from.x) and the band still lands: room 0's
	# centre (43, 33) to room 1's (13, 13): left, then up.
	_assert_carve_matches([Rect2i(40, 30, 6, 6), Rect2i(10, 10, 6, 6)], Vector2i(43, 33), Vector2i(13, 13), "left-up")


func test_a_corridor_between_two_rooms_on_one_row_is_only_the_band() -> void:
	# The L's degenerate case: no vertical leg, so nothing may be carved off
	# the row band. Room 0's centre (13, 13) to room 1's (43, 13).
	_assert_carve_matches([Rect2i(10, 10, 6, 6), Rect2i(40, 10, 6, 6)], Vector2i(13, 13), Vector2i(43, 13), "straight row")


func test_a_corridor_between_two_rooms_on_one_column_is_only_the_band() -> void:
	# The other straight case: no horizontal leg. Room 0's centre (13, 13) to
	# room 1's (13, 33): the 3-wide column band, no overshoot past either end.
	_assert_carve_matches([Rect2i(10, 10, 6, 6), Rect2i(10, 30, 6, 6)], Vector2i(13, 13), Vector2i(13, 33), "straight column")


func test_corridors_connect_every_room_placed() -> void:
	# Every room G9a1's placement puts down is joined: a flood fill over the
	# layout's walkable cells (rooms plus corridors) from the start room's
	# centre reaches every room's centre, on every seed and floor checked.
	for run_seed: int in SEEDS:
		for floor_index: int in FLOORS:
			var layout: FloorLayout = _layout(run_seed, floor_index)
			var origin: Vector2i = layout.start_room.center()
			var seen: Dictionary[Vector2i, bool] = {origin: true}
			var queue: Array[Vector2i] = [origin]
			var head: int = 0
			while head < queue.size():
				var cell: Vector2i = queue[head]
				head += 1
				for step: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					var next: Vector2i = cell + step
					if layout.is_walkable(next) and not seen.has(next):
						seen[next] = true
						queue.append(next)
			for room: RoomSpec in layout.rooms:
				assert_true(seen.has(room.center()), "seed %d floor %d: room %d unreachable" % [run_seed, floor_index, room.index])
