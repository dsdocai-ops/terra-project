extends GutTest
## Unit tests for the `Floor` node's own logic (W3-A2, G10a1): `paint` lays a
## generated `FloorLayout` out on the scene — the rooms in layout order, one
## door per door cell, the `AStarGrid2D` solids from the walkable data, the
## `painted` signal — and `room_at` maps a world position back to the room
## standing on the tile under it, agreeing with the layout's own
## `room_at_cell`. The tile kinds themselves are `tests/unit/test_floor_paint.gd`
## (G9b1); door locking and the Exit rule are G10a2's.

const SEEDS: Array[int] = [7, 42, 1234]

## Layouts the `painted` signal delivered, captured by a named method callback
## (lambdas never fire in GUT).
var _painted: Array[FloorLayout] = []


func _on_painted(layout: FloorLayout) -> void:
	_painted.append(layout)


func _make_world() -> World:
	var world := (load("res://scenes/main/world.tscn") as PackedScene).instantiate() as World
	world.debug_test_floor = false
	add_child_autofree(world)
	return world


## Paints a fresh layout for `run_seed` onto `world` and returns the Floor node
## (`floor_node.layout` holds the layout it was painted from).
func _painted_floor(world: World, run_seed: int) -> Floor:
	var layout: FloorLayout = FloorGenerator.generate(run_seed, 1, BiomeData.for_index(1), [] as Array[int])
	return _painted_floor_with_layout(world, layout)


func _painted_floor_with_layout(world: World, layout: FloorLayout) -> Floor:
	var floor_node := Floor.new()
	add_child_autofree(floor_node)
	_painted.clear()
	floor_node.painted.connect(_on_painted)
	floor_node.paint(layout, BiomeData.for_index(1), world)
	return floor_node


# --- paint: the rooms -------------------------------------------------------


func test_paint_lays_the_rooms_out_in_layout_order() -> void:
	for run_seed: int in SEEDS:
		var floor_node := _painted_floor(_make_world(), run_seed)
		var layout: FloorLayout = floor_node.layout
		assert_eq(floor_node.rooms.size(), layout.rooms.size(), "seed %d room count" % run_seed)
		for i: int in layout.rooms.size():
			var room := floor_node.rooms[i]
			assert_same(room.spec, layout.rooms[i], "seed %d room %d holds its spec" % [run_seed, i])
			assert_eq(room.type, layout.rooms[i].type, "seed %d room %d type" % [run_seed, i])
			assert_eq(room.name, "Room%d" % i, "seed %d room %d name" % [run_seed, i])


func test_paint_replaces_an_earlier_floors_rooms_and_doors() -> void:
	var world := _make_world()
	var floor_node := _painted_floor(world, 7)
	var first_rooms: Array[Room] = []
	for room: Room in floor_node.rooms:
		first_rooms.append(room)
	var second_layout: FloorLayout = FloorGenerator.generate(42, 1, BiomeData.for_index(1), [] as Array[int])
	_painted.clear()
	floor_node.paint(second_layout, BiomeData.for_index(1), world)
	# The rooms are the new layout's, in its order — none of the stale ones kept.
	assert_eq(floor_node.rooms.size(), second_layout.rooms.size(), "only the new layout's rooms")
	for stale: Room in first_rooms:
		assert_false(floor_node.rooms.has(stale), "the stale %s was not kept" % str(stale.name))
	for i: int in second_layout.rooms.size():
		assert_same(floor_node.rooms[i].spec, second_layout.rooms[i], "room %d is the new layout's" % i)
	# The door table was rebuilt for the new layout's indices.
	assert_eq(floor_node.doors_by_room.size(), second_layout.rooms.size(), "door table rebuilt")
	# And `painted` fired once per paint, never twice for one.
	assert_eq(_painted.size(), 1, "one painted emit per paint")


# --- paint: the doors -------------------------------------------------------


func test_paint_builds_one_door_per_door_cell() -> void:
	for run_seed: int in SEEDS:
		var floor_node := _painted_floor(_make_world(), run_seed)
		var total_doors: int = 0
		for room: Room in floor_node.rooms:
			var doors: Array = floor_node.doors_by_room.get(room.spec.index, [])
			assert_eq(doors.size(), room.spec.door_cells.size(),
				"seed %d room %d door count" % [run_seed, room.spec.index])
			var seen: Dictionary[Vector2i, bool] = {}
			for door: Door in doors:
				assert_true(room.spec.door_cells.has(door.cell),
					"seed %d room %d door cell %s is a spec door cell" % [run_seed, room.spec.index, str(door.cell)])
				assert_eq(door.position, Iso.to_screen(door.cell),
					"seed %d room %d door %s sits on its cell" % [run_seed, room.spec.index, str(door.cell)])
				seen[door.cell] = true
				total_doors += 1
			assert_eq(seen.size(), room.spec.door_cells.size(),
				"seed %d room %d has no two doors on one cell" % [run_seed, room.spec.index])
		var spec_doors: int = 0
		for spec: RoomSpec in floor_node.layout.rooms:
			spec_doors += spec.door_cells.size()
		assert_eq(total_doors, spec_doors, "seed %d total doors" % run_seed)


# --- paint: the path grid and the signal ------------------------------------


func test_paint_builds_the_astar_solids_from_the_walkable_data() -> void:
	for run_seed: int in SEEDS:
		var floor_node := _painted_floor(_make_world(), run_seed)
		assert_eq(floor_node.astar.region, Rect2i(0, 0, FloorGenerator.GRID, FloorGenerator.GRID),
			"seed %d region is the full grid" % run_seed)
		var problems: Array[String] = []
		for x: int in FloorGenerator.GRID:
			for y: int in FloorGenerator.GRID:
				var cell := Vector2i(x, y)
				var solid: bool = floor_node.astar.is_point_solid(cell)
				if solid == floor_node.layout.walkable.has(cell):
					problems.append("cell %s solid=%s walkable=%s" % [str(cell), str(solid), str(floor_node.layout.walkable.has(cell))])
		assert_eq(problems.size(), 0, "\n".join(problems.slice(0, 5)))


func test_paint_emits_painted_with_the_layout_once() -> void:
	var floor_node := _painted_floor(_make_world(), 42)
	assert_eq(_painted.size(), 1, "painted fired once")
	assert_same(_painted[0], floor_node.layout, "the signal carried the painted layout")


# --- room_at ----------------------------------------------------------------


func test_room_at_maps_every_room_interior_to_its_own_room() -> void:
	for run_seed: int in SEEDS:
		var floor_node := _painted_floor(_make_world(), run_seed)
		for room: Room in floor_node.rooms:
			var rect: Rect2i = room.spec.rect
			var cells: Array[Vector2i] = [
				rect.position,
				rect.position + Vector2i(rect.size.x - 1, 0),
				rect.position + Vector2i(0, rect.size.y - 1),
				rect.end - Vector2i.ONE,
				room.spec.center(),
				room.spec.anchor,
			]
			for cell: Vector2i in cells:
				assert_same(floor_node.room_at(Iso.to_screen(cell)), room,
					"seed %d room %d cell %s" % [run_seed, room.spec.index, str(cell)])


func test_room_at_returns_null_between_the_rooms_and_outside() -> void:
	for run_seed: int in SEEDS:
		var floor_node := _painted_floor(_make_world(), run_seed)
		var layout: FloorLayout = floor_node.layout
		# Every corridor cell (walkable, in no room's rect) maps to no room.
		var corridor_samples: int = 0
		for cell: Vector2i in layout.walkable:
			if layout.room_at_cell(cell) == null:
				corridor_samples += 1
				assert_null(floor_node.room_at(Iso.to_screen(cell)), "corridor %s" % str(cell))
		assert_gt(corridor_samples, 0, "seed %d has corridor cells" % run_seed)
		# Door cells sit just outside the rect, so they are no room either.
		for room: Room in floor_node.rooms:
			for cell: Vector2i in room.spec.door_cells:
				assert_null(floor_node.room_at(Iso.to_screen(cell)), "door cell %s" % str(cell))
		assert_null(floor_node.room_at(Iso.to_screen(Vector2i(-5, -5))), "off-grid tile")
		assert_null(floor_node.room_at(Vector2(99999.0, 99999.0)), "far off the floor")


func test_room_at_agrees_with_the_layouts_own_lookup_on_every_walkable_cell() -> void:
	var floor_node := _painted_floor(_make_world(), 42)
	var layout: FloorLayout = floor_node.layout
	var problems: Array[String] = []
	for cell: Vector2i in layout.walkable:
		var spec: RoomSpec = layout.room_at_cell(cell)
		var room: Room = floor_node.room_at(Iso.to_screen(cell))
		if spec == null and room != null:
			problems.append("cell %s found room %s, the layout found none" % [str(cell), str(room.name)])
		elif spec != null and room == null:
			problems.append("cell %s found no room, the layout found room %d" % [str(cell), spec.index])
		elif spec != null and room.spec.index != spec.index:
			problems.append("cell %s found room %d, the layout found room %d" % [str(cell), room.spec.index, spec.index])
	assert_eq(problems.size(), 0, "\n".join(problems.slice(0, 5)))


func test_room_at_reads_the_tile_under_a_position_not_the_exact_center() -> void:
	var floor_node := _painted_floor(_make_world(), 42)
	var room: Room = floor_node.rooms[0]
	var centre := Iso.to_screen(room.spec.center())
	var offsets: Array[Vector2] = [
		Vector2.ZERO,
		Vector2(Iso.HALF_W * 0.3, Iso.HALF_H * 0.3),
		Vector2(-Iso.HALF_W * 0.3, -Iso.HALF_H * 0.3),
		Vector2(Iso.HALF_W * 0.3, -Iso.HALF_H * 0.3),
		Vector2(-Iso.HALF_W * 0.3, Iso.HALF_H * 0.3),
	]
	for offset: Vector2 in offsets:
		assert_same(floor_node.room_at(centre + offset), room,
			"offset %s lands on the same tile" % str(offset))
