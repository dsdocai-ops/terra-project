extends GutTest
## Tests for `SpawnDirector` (SPEC-enemies-ai "Spawn director" and its Testing
## section, which names this file). Owned by enemies-ai. G12a1 covered the
## budget by floor; G12a2 adds the two spawn rules — the single wave (one
## `fill_room` call fields the whole budget, nothing held back) and the
## no-spawn-near-players check (`safe_cells`: `SAFE_RADIUS` around every
## player, with the too-small-room fallback) — plus the week-2 trio the wave
## fields and the seed determinism. The registry look-up proof is still to
## come and will extend this file.
##
## The budget table is `Scaling`'s constants (stats-status owns the tuning; the
## week-12 balance pass may move them), so no balance number is invented here:
## every expected value is recomposed from `Scaling.ENEMIES_PER_ROOM_*` and the
## clamp range, the way `Scaling.enemies_per_room` itself computes it, then
## floored at `SpawnDirector.MIN_ENEMIES`. What the test owns is the
## composition — the v1 floor at `MIN_ENEMIES` and the two seams: `room_budget`
## reads the spec's curve, and `fill_room` reads `room_budget` instead of
## re-deriving a second copy of the composition inline.

const SPAWN_DIRECTOR_PATH: String = "res://scripts/enemies/spawn_director.gd"
const SCALING_PATH: String = "res://scripts/scaling.gd"

## The floor range the budget is walked over, matching `Scaling`'s clamp range.
const FIRST_FLOOR: int = 1
const LAST_FLOOR: int = 30


## The budget recomposed from the constants, independently of
## `Scaling.enemies_per_room`: the curve's own arithmetic, then the v1 floor.
func _expected_budget(floor_index: int) -> int:
	var depth: int = clampi(floor_index, FIRST_FLOOR, LAST_FLOOR) - FIRST_FLOOR
	var curve: int = mini(Scaling.ENEMIES_PER_ROOM_BASE \
		+ floori(Scaling.ENEMIES_PER_ROOM_PER_FLOOR * float(depth)), \
		Scaling.ENEMIES_PER_ROOM_MAX)
	return maxi(curve, SpawnDirector.MIN_ENEMIES)


func test_the_budget_is_the_spec_curve_floored_at_min_enemies() -> void:
	for floor_index: int in range(FIRST_FLOOR, LAST_FLOOR + 1):
		assert_eq(SpawnDirector.room_budget(floor_index), _expected_budget(floor_index), \
			"floor %d fields exactly the recomposed budget" % floor_index)
		assert_eq(SpawnDirector.room_budget(floor_index), \
			maxi(Scaling.enemies_per_room(floor_index), SpawnDirector.MIN_ENEMIES), \
			"floor %d agrees with the curve read directly" % floor_index)


func test_the_floor_one_budget_is_the_curve_base_and_never_below_the_floor() -> void:
	assert_eq(SpawnDirector.room_budget(FIRST_FLOOR), \
		maxi(Scaling.ENEMIES_PER_ROOM_BASE, SpawnDirector.MIN_ENEMIES), \
		"floor 1 fields the curve's base count")
	assert_gte(SpawnDirector.room_budget(FIRST_FLOOR), SpawnDirector.MIN_ENEMIES, \
		"and the shallowest room never fields fewer than the v1 floor")


func test_the_budget_rises_with_depth_and_never_falls() -> void:
	var previous: int = 0
	for floor_index: int in range(FIRST_FLOOR, LAST_FLOOR + 1):
		var budget := SpawnDirector.room_budget(floor_index)
		assert_gte(budget, previous, "floor %d does not field fewer than the floor before" % floor_index)
		assert_lte(budget, Scaling.ENEMIES_PER_ROOM_MAX, \
			"floor %d stays under the curve's cap" % floor_index)
		previous = budget
	assert_gt(previous, SpawnDirector.room_budget(FIRST_FLOOR), \
		"the deepest floor really does field more than the first")


func test_the_budget_is_clamped_at_both_ends_of_the_floor_range() -> void:
	assert_eq(SpawnDirector.room_budget(0), SpawnDirector.room_budget(FIRST_FLOOR), \
		"clamped below the first floor")
	assert_eq(SpawnDirector.room_budget(-3), SpawnDirector.room_budget(FIRST_FLOOR), \
		"and for a negative floor")
	assert_eq(SpawnDirector.room_budget(LAST_FLOOR + 1), SpawnDirector.room_budget(LAST_FLOOR), \
		"clamped above the last")
	assert_eq(SpawnDirector.room_budget(9999), SpawnDirector.room_budget(LAST_FLOOR), \
		"however deep the index goes")


func test_the_budget_reads_the_spec_curve_not_a_second_table() -> void:
	var source := FileAccess.get_file_as_string(SPAWN_DIRECTOR_PATH)
	assert_gt(source.length(), 0, "scripts/enemies/spawn_director.gd is readable")
	assert_true(source.contains("Scaling.enemies_per_room(floor_index)"), \
		"room_budget reads the spec's curve, the one place the budget table lives")
	assert_true(source.contains("maxi(Scaling.enemies_per_room(floor_index), MIN_ENEMIES)"), \
		"and the v1 floor at MIN_ENEMIES is part of the composition")


func test_fill_room_reads_the_budget_function_not_an_inline_second_copy() -> void:
	var source := FileAccess.get_file_as_string(SPAWN_DIRECTOR_PATH)
	assert_true(source.contains("var count: int = room_budget(floor_index)"), \
		"fill_room's wave count is room_budget's")
	assert_eq(source.count( \
		"return maxi(Scaling.enemies_per_room(floor_index), MIN_ENEMIES)"), 1, \
		"the composition appears once, in room_budget — no second copy to drift")


# --- G12a2: the spawn rules (pure `safe_cells`, then `fill_room` itself) ---

const WORLD_SCENE_PATH: String = "res://scenes/main/world.tscn"
const PLAYER_SCENE_PATH: String = "res://scenes/player/player.tscn"

## The week-2 trio (G8's data): the only kinds a v1 wave may field.
const TRIO: Array[StringName] = [&"hollow_miner", &"rock_tick", &"lantern_wisp"]

var _world: World = null


func after_each() -> void:
	NetworkManager.players.erase(1)
	NetworkManager.players.erase(2)
	GameState.world = null
	_world = null
	Enemy.reset_separation_cache()


# The pure safe-cell filter. `Iso` tiles are 64x32 (HALF_W 32), so a cell 20
# tiles down the row sits 640 px from its neighbour — far past SAFE_RADIUS —
# and adjacent cells sit 32 px apart, well inside it.


func test_a_cell_within_the_safe_radius_of_a_player_is_dropped() -> void:
	var points: Array[Vector2i] = [Vector2i(10, 0), Vector2i(30, 0), Vector2i(50, 0)]
	var players: Array[Vector2] = [Iso.to_screen(Vector2i(10, 0))]
	var kept: Array[Vector2i] = SpawnDirector.safe_cells(points, players, \
		SpawnDirector.SAFE_RADIUS, 1)
	assert_eq(kept.size(), 2, "the two cells clear of the player survive")
	assert_true(kept.has(Vector2i(30, 0)) and kept.has(Vector2i(50, 0)), \
		"and they are the far ones — the cell under the player is gone")


func test_a_cell_near_any_one_of_several_players_is_dropped() -> void:
	var points: Array[Vector2i] = [Vector2i(10, 0), Vector2i(30, 0), Vector2i(50, 0)]
	var players: Array[Vector2] = [ \
		Iso.to_screen(Vector2i(50, 0)) + Vector2(100.0, 0.0), \
		Iso.to_screen(Vector2i(30, 0))]
	var kept: Array[Vector2i] = SpawnDirector.safe_cells(points, players, \
		SpawnDirector.SAFE_RADIUS, 1)
	assert_eq(kept, [Vector2i(10, 0)] as Array[Vector2i], \
		"a cell clear of the first player but inside the second's radius is dropped too")


func test_the_radius_boundary_drops_inside_and_keeps_exactly_at_it() -> void:
	# SPEC-enemies-ai: "Spawn positions avoid 160 px around players" — a cell
	# exactly AT the radius is not within it, so it stays safe. Pinned on both
	# sides of the edge on purpose.
	var cell: Vector2i = Vector2i(10, 0)
	var points: Array[Vector2i] = [cell, Vector2i(200, 0)]
	var just_inside: Array[Vector2] = [Iso.to_screen(cell) + Vector2(SpawnDirector.SAFE_RADIUS - 1.0, 0.0)]
	var exactly_at: Array[Vector2] = [Iso.to_screen(cell) + Vector2(SpawnDirector.SAFE_RADIUS, 0.0)]
	assert_false(SpawnDirector.safe_cells(points, just_inside, SpawnDirector.SAFE_RADIUS, 1) \
		.has(cell), "just inside the radius (159 px) is dropped")
	assert_true(SpawnDirector.safe_cells(points, exactly_at, SpawnDirector.SAFE_RADIUS, 1) \
		.has(cell), "exactly at the radius (160 px) is kept")


func test_no_players_leaves_every_spawn_point_safe() -> void:
	var points: Array[Vector2i] = [Vector2i(10, 0), Vector2i(30, 0), Vector2i(50, 0)]
	assert_eq(SpawnDirector.safe_cells(points, [], SpawnDirector.SAFE_RADIUS, 1), points, \
		"an empty player list drops nothing")


func test_the_fallback_returns_every_spawn_point_when_too_few_are_safe() -> void:
	var points: Array[Vector2i] = [Vector2i(10, 0), Vector2i(11, 0), Vector2i(300, 0)]
	var players: Array[Vector2] = [Iso.to_screen(Vector2i(10, 0)), Iso.to_screen(Vector2i(11, 0))]
	assert_eq(SpawnDirector.safe_cells(points, players, SpawnDirector.SAFE_RADIUS, \
		SpawnDirector.MIN_ENEMIES), points, \
		"one safe cell is below the minimum — the room is too small to be safe, so every spawn point comes back")


func test_the_fallback_does_not_fire_when_exactly_the_minimum_survive() -> void:
	var points: Array[Vector2i] = [Vector2i(10, 0), Vector2i(11, 0), Vector2i(300, 0), Vector2i(320, 0)]
	var players: Array[Vector2] = [Iso.to_screen(Vector2i(10, 0))]
	var kept: Array[Vector2i] = SpawnDirector.safe_cells(points, players, \
		SpawnDirector.SAFE_RADIUS, SpawnDirector.MIN_ENEMIES)
	assert_eq(kept.size(), SpawnDirector.MIN_ENEMIES, \
		"exactly the minimum survived, so no fallback")
	assert_false(kept.has(Vector2i(10, 0)), "and the blocked cell is still dropped")
	assert_false(kept.has(Vector2i(11, 0)), "the near cell 45 px away is blocked too")


func test_safe_cells_never_touches_the_input_array() -> void:
	var points: Array[Vector2i] = [Vector2i(10, 0), Vector2i(11, 0)]
	var players: Array[Vector2] = [Iso.to_screen(Vector2i(10, 0))]
	SpawnDirector.safe_cells(points, players, SpawnDirector.SAFE_RADIUS, 1)
	assert_eq(points, [Vector2i(10, 0), Vector2i(11, 0)] as Array[Vector2i], \
		"the filter reads the caller's array, it does not own it")


func test_the_safe_radius_is_the_spec_value() -> void:
	assert_eq(SpawnDirector.SAFE_RADIUS, 160.0, \
		"SPEC-enemies-ai: spawn positions avoid 160 px around players")


# `fill_room` itself, on a real World and the real enemy base scene: the
# offline peer is the server, so the spawn runs exactly as the host's does.


func _wire_world() -> void:
	_world = (load(WORLD_SCENE_PATH) as PackedScene).instantiate() as World
	_world.debug_test_floor = false
	add_child_autofree(_world)
	GameState.world = _world


func _add_player(peer: int, pos: Vector2) -> Player:
	var player: Player = (load(PLAYER_SCENE_PATH) as PackedScene).instantiate() as Player
	add_child_autofree(player)
	player.global_position = pos
	NetworkManager.players[peer] = player
	return player


func _spec(points: Array[Vector2i], index: int = 3, room_type: int = FloorGenerator.RoomType.COMBAT) -> RoomSpec:
	var spec := RoomSpec.new()
	spec.index = index
	spec.type = room_type
	spec.spawn_points = points
	return spec


func _room(spec: RoomSpec) -> Room:
	var room: Room = Room.new()
	room.spec = spec
	room.type = spec.type
	add_child_autofree(room)
	return room


func _far_points(count: int, start_x: int = 40) -> Array[Vector2i]:
	var points: Array[Vector2i] = []
	for index: int in count:
		points.append(Vector2i(start_x + index * 20, 0))
	return points


func test_one_fill_room_call_spawns_the_whole_budget_as_a_single_wave() -> void:
	_wire_world()
	var room := _room(_spec(_far_points(8)))
	var spawned: Array[Enemy] = SpawnDirector.fill_room(room)
	assert_eq(spawned.size(), SpawnDirector.room_budget(1), \
		"one call fields the whole floor-1 budget — a single wave, nothing held back")
	for enemy: Enemy in spawned:
		assert_eq(enemy.get_parent(), _world.entities, "each spawn sits under World/Entities")
		assert_not_null(enemy.data, "each spawn carries its EnemyData")


func test_no_enemy_spawns_within_the_safe_radius_of_a_player() -> void:
	_wire_world()
	var blocked: Array[Vector2i] = [Vector2i(10, 0), Vector2i(11, 0)]
	var far_cells: Array[Vector2i] = _far_points(6)
	var points: Array[Vector2i] = []
	points.append_array(blocked)
	points.append_array(far_cells)
	var player: Player = _add_player(1, Iso.to_screen(Vector2i(10, 0)))
	var room := _room(_spec(points))
	var spawned: Array[Enemy] = SpawnDirector.fill_room(room)
	var far_screens: Array[Vector2] = []
	for cell: Vector2i in far_cells:
		far_screens.append(Iso.to_screen(cell))
	assert_eq(spawned.size(), SpawnDirector.room_budget(1), \
		"enough safe cells: the wave still fields the whole budget")
	for enemy: Enemy in spawned:
		assert_gte(enemy.position.distance_to(player.position), SpawnDirector.SAFE_RADIUS, \
			"no spawn within the player-distance threshold")
		assert_true(far_screens.has(enemy.position), \
			"every spawn sat on a safe cell, never a blocked one")


func test_a_room_too_small_to_be_safe_still_fields_its_wave() -> void:
	_wire_world()
	var points: Array[Vector2i] = [Vector2i(10, 0), Vector2i(11, 0), Vector2i(12, 0), Vector2i(13, 0)]
	var player: Player = _add_player(1, Iso.to_screen(Vector2i(11, 0)))
	var room := _room(_spec(points))
	var spawned: Array[Enemy] = SpawnDirector.fill_room(room)
	var screens: Array[Vector2] = []
	for cell: Vector2i in points:
		screens.append(Iso.to_screen(cell))
	assert_eq(spawned.size(), SpawnDirector.room_budget(1), \
		"the fallback still fields the whole budget")
	var within: int = 0
	for enemy: Enemy in spawned:
		assert_true(screens.has(enemy.position), "the spawn sat on a real spawn point")
		if enemy.position.distance_to(player.position) < SpawnDirector.SAFE_RADIUS:
			within += 1
	assert_gt(within, 0, "the room was genuinely too small to be safe — the fallback really fired")


func test_the_wave_fields_the_week_2_trio_data() -> void:
	_wire_world()
	var room := _room(_spec(_far_points(8)))
	var spawned: Array[Enemy] = SpawnDirector.fill_room(room)
	for enemy: Enemy in spawned:
		assert_not_null(enemy.data, "each spawn resolved its EnemyData")
		assert_true(TRIO.has(enemy.data.id), \
			"'%s' is week-2 trio data, not a placeholder kind" % enemy.data.id)
	assert_eq(SpawnDirector.DEFAULT_POOL.size(), 3, "the pool names exactly the trio")
	for entry: Array in SpawnDirector.DEFAULT_POOL:
		assert_true(TRIO.has(StringName(entry[0])), "'%s' is a trio kind" % entry[0])
		assert_not_null(EnemyData.find(StringName(entry[0])), "the kind's G8 data loads")


func test_fill_room_is_deterministic_given_the_seed() -> void:
	_wire_world()
	var points: Array[Vector2i] = _far_points(8)
	var first: Array[Enemy] = SpawnDirector.fill_room(_room(_spec(points, 3)))
	var second: Array[Enemy] = SpawnDirector.fill_room(_room(_spec(points, 3)))
	assert_eq(first.size(), second.size(), "both rooms fielded the same wave size")
	for index: int in first.size():
		assert_eq(second[index].position, first[index].position, \
			"same run seed and room index: spawn %d lands on the same cell" % index)
	var third: Array[Enemy] = SpawnDirector.fill_room(_room(_spec(points, 4)))
	var differs: bool = third.size() != first.size()
	for index: int in mini(third.size(), first.size()):
		if third[index].position != first[index].position:
			differs = true
	assert_true(differs, "a different room index mixes the seed differently — the arrangement is not fixed")
