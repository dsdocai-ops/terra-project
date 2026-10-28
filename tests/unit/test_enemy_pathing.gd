extends GutTest
## The pure `EnemyPathing` behind the enemy routing (SPEC-enemies-ai
## "Pathfinding"): the A* route over the floor's `AStarGrid2D`, the reached
## waypoints trimmed, the next waypoint picked. The closing cases run the real
## enemy scene against a real generated floor's grid and prove its
## `_next_waypoint` returns exactly the pure file's answer. Owned by enemies-ai.

const ENEMY_SCENE := "res://scenes/enemies/enemy.tscn"
const WORLD_SCENE := "res://scenes/main/world.tscn"
const LAYOUT_SEED: int = 42
## The unit grids mirror `Floor._build_astar`'s config at a hand-held size.
const GRID: int = 16

var _enemy: Enemy = null
var _world: World = null


# --- the grid helper --------------------------------------------------------------


func _grid(solids: Array[Vector2i]) -> AStarGrid2D:
	var astar := AStarGrid2D.new()
	astar.region = Rect2i(0, 0, GRID, GRID)
	astar.cell_size = Vector2.ONE
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	astar.update()
	for cell: Vector2i in solids:
		astar.set_point_solid(cell, true)
	return astar


func _path_tiles(path: PackedVector2Array) -> Array[Vector2i]:
	var tiles: Array[Vector2i] = []
	for point: Vector2 in path:
		tiles.append(Iso.to_tile(point))
	return tiles


# --- the route reaches its target ---------------------------------------------------


func test_the_path_reaches_its_target() -> void:
	var from_cell := Vector2i(2, 2)
	var to_cell := Vector2i(10, 6)
	var path := EnemyPathing.build_path(_grid([]), Iso.to_screen(from_cell), Iso.to_screen(to_cell))
	assert_gt(path.size(), 0, "an open grid has a route")
	assert_eq(Iso.to_tile(path[path.size() - 1]), to_cell, "the last waypoint is the target tile")


func test_the_path_starts_one_step_from_the_start_tile() -> void:
	var from_cell := Vector2i(2, 2)
	var path := EnemyPathing.build_path(_grid([]), Iso.to_screen(from_cell), Iso.to_screen(Vector2i(5, 3)))
	assert_ne(Iso.to_tile(path[0]), from_cell, "the start tile's own center is not a waypoint")


func test_the_path_routes_around_a_blocked_tile() -> void:
	var blocked := Vector2i(5, 2)
	var from_cell := Vector2i(2, 2)
	var to_cell := Vector2i(8, 2)
	var path := EnemyPathing.build_path(_grid([blocked]), Iso.to_screen(from_cell), Iso.to_screen(to_cell))
	var tiles := _path_tiles(path)
	assert_false(tiles.has(blocked), "no waypoint sits on the blocked tile")
	assert_eq(tiles[tiles.size() - 1], to_cell, "the detour still reaches the target")
	var left_the_line := false
	for tile: Vector2i in tiles:
		if tile.y != from_cell.y:
			left_the_line = true
	assert_true(left_the_line, "the path actually leaves the straight line to get around")


func test_a_corner_with_one_open_orthogonal_still_routes() -> void:
	var path := EnemyPathing.build_path(_grid([Vector2i(1, 0)]), Iso.to_screen(Vector2i(0, 0)), Iso.to_screen(Vector2i(1, 1)))
	var tiles := _path_tiles(path)
	assert_false(tiles.has(Vector2i(1, 0)), "the route avoids the solid neighbour")
	assert_eq(tiles[tiles.size() - 1], Vector2i(1, 1), "and still reaches the diagonal target")


func test_a_walled_in_start_has_no_route_and_pursues_directly() -> void:
	# (0,0)'s both orthogonal neighbours are solid, so the diagonal across them
	# is disallowed too — nothing leads out, and `goal` falls back to the point.
	var path := EnemyPathing.build_path(_grid([Vector2i(1, 0), Vector2i(0, 1)]), Iso.to_screen(Vector2i(0, 0)), Iso.to_screen(Vector2i(2, 2)))
	assert_true(path.is_empty(), "no route leads out of the corner")
	assert_eq(EnemyPathing.goal(path, Vector2(7, 7)), Vector2(7, 7), "the pursuit falls back to the direct point")


# --- the direct-pursuit fallbacks -----------------------------------------------------


func test_a_solid_target_falls_back_to_direct_pursuit() -> void:
	var target := Vector2i(6, 6)
	var path := EnemyPathing.build_path(_grid([target]), Iso.to_screen(Vector2i(2, 2)), Iso.to_screen(target))
	assert_eq(path, PackedVector2Array([Iso.to_screen(target)]))


func test_a_solid_start_falls_back_to_direct_pursuit() -> void:
	var start := Vector2i(2, 2)
	var goal := Iso.to_screen(Vector2i(6, 6))
	var path := EnemyPathing.build_path(_grid([start]), Iso.to_screen(start), goal)
	assert_eq(path, PackedVector2Array([goal]))


func test_an_out_of_region_end_falls_back_to_direct_pursuit() -> void:
	var goal := Iso.to_screen(Vector2i(GRID + 4, GRID + 4))
	var path := EnemyPathing.build_path(_grid([]), Iso.to_screen(Vector2i(2, 2)), goal)
	assert_eq(path, PackedVector2Array([goal]))


# --- the waypoint stepping -------------------------------------------------------------


func test_the_arrival_radius_is_the_old_trim_literal() -> void:
	assert_eq(EnemyPathing.ARRIVAL_RADIUS, 10.0)


func test_advance_drops_waypoints_the_body_has_reached() -> void:
	var path := PackedVector2Array([Iso.to_screen(Vector2i(1, 1)), Iso.to_screen(Vector2i(2, 2)), Iso.to_screen(Vector2i(3, 3))])
	var trimmed := EnemyPathing.advance(path, Iso.to_screen(Vector2i(1, 1)), EnemyPathing.ARRIVAL_RADIUS)
	assert_eq(trimmed.size(), 2, "the reached waypoint is dropped")
	assert_eq(Iso.to_tile(trimmed[0]), Vector2i(2, 2), "the next waypoint is the second tile")


func test_advance_keeps_a_waypoint_at_the_arrival_edge() -> void:
	var first := Vector2(100, 100)
	var path := PackedVector2Array([first, Vector2(200, 100)])
	var at_edge := first + Vector2(EnemyPathing.ARRIVAL_RADIUS, 0)
	var inside := first + Vector2(EnemyPathing.ARRIVAL_RADIUS - 0.01, 0)
	assert_eq(EnemyPathing.advance(path, at_edge, EnemyPathing.ARRIVAL_RADIUS).size(), 2, "exactly at the radius is not within it")
	assert_eq(EnemyPathing.advance(path, inside, EnemyPathing.ARRIVAL_RADIUS).size(), 1, "just inside it, the waypoint is dropped")


func test_goal_returns_the_first_waypoint_then_the_fallback() -> void:
	var path := PackedVector2Array([Vector2(30, 48), Vector2(64, 64)])
	assert_eq(EnemyPathing.goal(path, Vector2(7, 7)), Vector2(30, 48))
	assert_eq(EnemyPathing.goal(PackedVector2Array(), Vector2(7, 7)), Vector2(7, 7), "an empty path pursues directly")


# --- the enemy scene paths through this file ---------------------------------------------


func before_each() -> void:
	_enemy = (load(ENEMY_SCENE) as PackedScene).instantiate() as Enemy
	assert_true(_enemy.setup(&"hollow_miner"), "hollow_miner data loads")
	add_child_autofree(_enemy)
	_world = (load(WORLD_SCENE) as PackedScene).instantiate() as World
	_world.debug_test_floor = false
	add_child_autofree(_world)
	var floor_node := Floor.new()
	floor_node.layout = FloorGenerator.generate(LAYOUT_SEED, 1, BiomeData.for_index(1), [])
	floor_node._build_astar()
	add_child_autofree(floor_node)
	_world.floor_node = floor_node
	GameState.world = _world


func after_each() -> void:
	GameState.world = null


## The layout's first and farthest walkable tiles: a connected pair any two
## points of the floor can path between (the soak proves the floor connected).
func _far_cells() -> Array[Vector2i]:
	var start := Vector2i(-1, -1)
	for cell: Vector2i in _world.floor_node.layout.walkable:
		if start == Vector2i(-1, -1) or cell.x + cell.y < start.x + start.y:
			start = cell
	var far := start
	for cell: Vector2i in _world.floor_node.layout.walkable:
		if cell.x + cell.y > far.x + far.y:
			far = cell
	var cells: Array[Vector2i] = [start, far]
	return cells


func test_the_enemy_scene_next_waypoint_is_the_pure_path_first_waypoint() -> void:
	var cells := _far_cells()
	_enemy.global_position = Iso.to_screen(cells[0])
	var goal := Iso.to_screen(cells[1])
	var waypoint: Vector2 = _enemy._next_waypoint(goal)
	var pure := EnemyPathing.build_path(_world.floor_node.astar, Iso.to_screen(cells[0]), goal)
	assert_gt(pure.size(), 0, "the generated floor connects the two cells")
	assert_eq(waypoint, EnemyPathing.goal(pure, goal), "the scene steers at the pure path's first waypoint")


func test_the_enemy_scene_trims_a_reached_waypoint_through_the_pure_file() -> void:
	var cells := _far_cells()
	_enemy.global_position = Iso.to_screen(cells[0])
	var goal := Iso.to_screen(cells[1])
	var first: Vector2 = _enemy._next_waypoint(goal)
	_enemy.global_position = first
	var second: Vector2 = _enemy._next_waypoint(goal)
	var pure := EnemyPathing.build_path(_world.floor_node.astar, Iso.to_screen(cells[0]), goal)
	var advanced := EnemyPathing.advance(pure, first, EnemyPathing.ARRIVAL_RADIUS)
	assert_eq(second, EnemyPathing.goal(advanced, goal), "the scene's next goal is the pure path advanced past the first waypoint")


func test_with_no_floor_the_enemy_pursues_directly() -> void:
	GameState.world = null
	var goal := Vector2(100, 50)
	assert_eq(_enemy._next_waypoint(goal), goal, "no floor: the waypoint is the point itself")
