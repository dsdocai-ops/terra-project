extends GutTest
## Unit mirror of `scripts/generation/floor_paint.gd` (W3-A1, G9b1): the tile
## kinds of SPEC-floor-generation step 5 — "floor tiles, wall tiles around every
## walkable cell, pit tiles elsewhere" — plus the wiring test that the real
## `Floor._paint_tiles` puts exactly those kinds on the World's layers.

const GRID: int = 96


## A minimal layout: three walkable cells meeting at a corner.
func _tiny_layout() -> FloorLayout:
	var layout := FloorLayout.new()
	layout.walkable[Vector2i(4, 4)] = true
	layout.walkable[Vector2i(5, 4)] = true
	layout.walkable[Vector2i(5, 5)] = true
	return layout


func test_floor_is_exactly_the_walkable_cells() -> void:
	var layout := _tiny_layout()
	var paint := FloorPaint.new(layout)
	for cell: Vector2i in [Vector2i(4, 4), Vector2i(5, 4), Vector2i(5, 5)]:
		assert_eq(paint.kind(cell), FloorPaint.Kind.FLOOR, "walkable %s paints floor" % str(cell))
	for cell: Vector2i in [Vector2i(3, 3), Vector2i(0, 0), Vector2i(6, 6)]:
		assert_ne(paint.kind(cell), FloorPaint.Kind.FLOOR, "non-walkable %s is no floor" % str(cell))


func test_walls_ring_every_walkable_cell_including_diagonals() -> void:
	var layout := _tiny_layout()
	var paint := FloorPaint.new(layout)
	# Every non-walkable 8-neighbour of the three walkable cells is a wall.
	for cell: Vector2i in [Vector2i(3, 3), Vector2i(3, 4), Vector2i(3, 5), Vector2i(4, 3),
			Vector2i(5, 3), Vector2i(6, 3), Vector2i(6, 4), Vector2i(6, 5), Vector2i(6, 6),
			Vector2i(5, 6), Vector2i(4, 5)]:
		assert_eq(paint.kind(cell), FloorPaint.Kind.WALL, "%s touches walkable, paints wall" % str(cell))
	# And no walkable cell's neighbourhood hides a non-wall gap.
	for cell: Vector2i in layout.walkable:
		for dx: int in range(-1, 2):
			for dy: int in range(-1, 2):
				var near: Vector2i = cell + Vector2i(dx, dy)
				assert_ne(paint.kind(near), FloorPaint.Kind.PIT,
					"%s beside walkable %s is no pit" % [str(near), str(cell)])


func test_pit_is_everything_else() -> void:
	var layout := _tiny_layout()
	var paint := FloorPaint.new(layout)
	assert_eq(paint.kind(Vector2i(0, 0)), FloorPaint.Kind.PIT, "a far corner is pit")
	assert_eq(paint.kind(Vector2i(9, 9)), FloorPaint.Kind.PIT, "past the ring is pit")
	assert_eq(paint.kind(Vector2i(100, 100)), FloorPaint.Kind.PIT, "outside the grid is pit")


func test_every_grid_cell_is_exactly_one_kind() -> void:
	var paint := FloorPaint.new(_tiny_layout())
	var floors: int = 0
	var walls: int = 0
	var pits: int = 0
	for x: int in GRID:
		for y: int in GRID:
			match paint.kind(Vector2i(x, y)):
				FloorPaint.Kind.FLOOR: floors += 1
				FloorPaint.Kind.WALL: walls += 1
				FloorPaint.Kind.PIT: pits += 1
	assert_eq(floors, 3, "the three walkable cells")
	assert_eq(floors + walls + pits, GRID * GRID, "every cell sorted into one kind")
	assert_eq(walls, paint.wall_cells().size(), "the wall ring is what wall_cells lists")


func test_wall_cells_are_row_major_and_clamped_to_the_grid() -> void:
	var paint := FloorPaint.new(_tiny_layout())
	var walls: Array[Vector2i] = paint.wall_cells()
	assert_gt(walls.size(), 0, "the ring is not empty")
	var previous := Vector2i(-1, -1)
	for cell: Vector2i in walls:
		assert_true(cell.y > previous.y or (cell.y == previous.y and cell.x > previous.x),
			"%s follows %s in row-major order" % [str(cell), str(previous)])
		previous = cell
	# A grid override clamps the ring to it: a 6x6 grid ends at cell 5.
	var small := FloorPaint.new(_tiny_layout(), 6)
	for cell: Vector2i in small.wall_cells():
		assert_true(cell.x >= 0 and cell.y >= 0 and cell.x < 6 and cell.y < 6,
			"%s stays inside the 6x6 override" % str(cell))


# --- the wiring: Floor._paint_tiles paints these kinds -------------------------


func test_the_real_paint_puts_the_three_kinds_on_the_worlds_layers() -> void:
	var world := (load("res://scenes/main/world.tscn") as PackedScene).instantiate() as World
	world.debug_test_floor = false
	add_child_autofree(world)
	var layout: FloorLayout = FloorGenerator.generate(42, 1, BiomeData.for_index(1), [] as Array[int])
	var floor_node := Floor.new()
	add_child_autofree(floor_node)
	floor_node.layout = layout
	floor_node._paint_tiles(world, BiomeData.for_index(1))
	var paint := FloorPaint.new(layout)
	var problems: Array[String] = []
	var painted_walls: int = 0
	for x: int in FloorGenerator.GRID:
		for y: int in FloorGenerator.GRID:
			var cell := Vector2i(x, y)
			var kind: int = paint.kind(cell)
			var floor_coords: Vector2i = world.floor_layer.get_cell_atlas_coords(cell)
			var wall_source: int = world.walls_layer.get_cell_source_id(cell)
			if kind == FloorPaint.Kind.FLOOR:
				if floor_coords != Tiles.floor_at(cell) or wall_source != -1:
					problems.append("floor cell %s painted %s/%d" % [str(cell), str(floor_coords), wall_source])
			elif kind == FloorPaint.Kind.WALL:
				painted_walls += 1
				# A wall cell carries no floor tile and a wall above.
				if wall_source == -1 or floor_coords != Vector2i(-1, -1):
					problems.append("wall cell %s painted %s/%d" % [str(cell), str(floor_coords), wall_source])
			else:
				if floor_coords != Tiles.PIT or wall_source != -1:
					problems.append("pit cell %s painted %s/%d" % [str(cell), str(floor_coords), wall_source])
	assert_eq(problems.size(), 0, "\n".join(problems.slice(0, 5)))
	assert_eq(painted_walls, paint.wall_cells().size(), "every wall-ring cell got its wall")


func test_the_painted_layers_read_back_the_walkable_custom_data() -> void:
	# Step 5's "set the walkable custom data", read back through World.is_walkable:
	# exactly the layout's walkable cells, walls blocking from above and pits
	# carrying a non-walkable tile.
	var world := (load("res://scenes/main/world.tscn") as PackedScene).instantiate() as World
	world.debug_test_floor = false
	add_child_autofree(world)
	var layout: FloorLayout = FloorGenerator.generate(42, 1, BiomeData.for_index(1), [] as Array[int])
	var floor_node := Floor.new()
	add_child_autofree(floor_node)
	floor_node.layout = layout
	floor_node._paint_tiles(world, BiomeData.for_index(1))
	var paint := FloorPaint.new(layout)
	var problems: Array[String] = []
	for x: int in FloorGenerator.GRID:
		for y: int in FloorGenerator.GRID:
			var cell := Vector2i(x, y)
			var walkable: bool = world.is_walkable(cell)
			var kind: int = paint.kind(cell)
			if kind == FloorPaint.Kind.FLOOR and not walkable:
				problems.append("floor cell %s reads non-walkable" % str(cell))
			if kind != FloorPaint.Kind.FLOOR and walkable:
				problems.append("%s cell %s reads walkable" % ["wall" if kind == FloorPaint.Kind.WALL else "pit", str(cell)])
	assert_eq(problems.size(), 0, "\n".join(problems.slice(0, 5)))
