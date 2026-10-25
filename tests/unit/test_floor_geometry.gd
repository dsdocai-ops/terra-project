extends GutTest
## Room size, spacing and corridor corners from FloorGenerator.

const SEEDS: Array[int] = [1, 7, 42, 1234, 99991]


func _layout(run_seed: int, floor_index: int = 1) -> FloorLayout:
	return FloorGenerator.generate(run_seed, floor_index, BiomeData.for_index(1), [])


func test_rooms_never_overlap_and_keep_the_gap() -> void:
	for run_seed: int in SEEDS:
		var layout: FloorLayout = _layout(run_seed)
		for a: int in layout.rooms.size():
			for b: int in range(a + 1, layout.rooms.size()):
				var grown: Rect2i = layout.rooms[a].rect.grow(FloorGenerator.ROOM_GAP)
				assert_false(grown.intersects(layout.rooms[b].rect), "seed %d rooms %d/%d too close" % [run_seed, a, b])


func test_rooms_are_at_least_the_biome_minimum() -> void:
	var biome: BiomeData = BiomeData.for_index(1)
	for run_seed: int in SEEDS:
		for room: RoomSpec in _layout(run_seed).rooms:
			assert_gte(room.rect.size.x, 9)
			assert_gte(room.rect.size.y, 7)
	assert_gte(biome.room_size_min.x, 12, "rooms were enlarged")


func test_corridor_turns_have_a_full_corner() -> void:
	var cells: Dictionary[Vector2i, bool] = {}
	var rects: Array[Rect2i] = [Rect2i(10, 10, 6, 6), Rect2i(40, 40, 6, 6)]
	var carved: Array[Vector2i] = FloorGenerator._carve_corridors(rects, [Vector2i(0, 1)])
	for cell: Vector2i in carved:
		cells[cell] = true
	# Room 0 centre (13, 13), room 1 centre (43, 43): the turn is at (43, 13).
	for dx: int in range(-1, 2):
		for dy: int in range(-1, 2):
			assert_true(cells.has(Vector2i(43 + dx, 13 + dy)), "corner cell %d,%d" % [dx, dy])
