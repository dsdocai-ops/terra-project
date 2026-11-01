extends GutTest
## Tests for `SpawnDirector` (SPEC-enemies-ai "Spawn director" and its Testing
## section, which names this file). Owned by enemies-ai. G12a1 covered the
## budget by floor; G12a2 adds the two spawn rules — the single wave (one
## `fill_room` call fields the whole budget, nothing held back) and the
## no-spawn-near-players check (`safe_cells`: `SAFE_RADIUS` around every
## player, with no exception — the judge-rejected too-small-room fallback is
## gone, a room with no safe cell fields nothing) — plus the week-2 trio the
## wave fields and the seed determinism. G12b adds the registry look-up: the
## registration existed on disk all along (`register_populators` arms
## `arm_room` for COMBAT and ELITE_COMBAT, `main.gd` calls it at startup), so
## the proof is that the looked-up callable reaches `fill_room` once per room
## activation — no second registration was added.
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
	assert_true(source.contains("SpawnWaves.plan(room_budget(floor_index), rng)"), \
		"fill_room's wave plan is built from room_budget")
	assert_eq(source.count( \
		"return maxi(Scaling.enemies_per_room(floor_index), MIN_ENEMIES)"), 1, \
		"the composition appears once, in room_budget — no second copy to drift")


# --- G12a2: the spawn rules (pure `safe_cells`, then `fill_room` itself) ---

const WORLD_SCENE_PATH: String = "res://scenes/main/world.tscn"
const PLAYER_SCENE_PATH: String = "res://scenes/player/player.tscn"

## The week-2 trio (G8's data): the only kinds a v1 wave may field.
const TRIO: Array[StringName] = [&"hollow_miner", &"rock_tick", &"lantern_wisp"]

var _world: World = null


func before_each() -> void:
	FloorGenerator.clear_populators()


func after_each() -> void:
	NetworkManager.players.erase(1)
	NetworkManager.players.erase(2)
	GameState.world = null
	_world = null
	Enemy.reset_separation_cache()
	FloorGenerator.clear_populators()


# The pure safe-cell filter. `Iso` tiles are 64x32 (HALF_W 32), so a cell 20
# tiles down the row sits 640 px from its neighbour — far past SAFE_RADIUS —
# and adjacent cells sit 32 px apart, well inside it.


func test_a_cell_within_the_safe_radius_of_a_player_is_dropped() -> void:
	var points: Array[Vector2i] = [Vector2i(10, 0), Vector2i(30, 0), Vector2i(50, 0)]
	var players: Array[Vector2] = [Iso.to_screen(Vector2i(10, 0))]
	var kept: Array[Vector2i] = SpawnDirector.safe_cells(points, players, \
		SpawnDirector.SAFE_RADIUS)
	assert_eq(kept.size(), 2, "the two cells clear of the player survive")
	assert_true(kept.has(Vector2i(30, 0)) and kept.has(Vector2i(50, 0)), \
		"and they are the far ones — the cell under the player is gone")


func test_a_cell_near_any_one_of_several_players_is_dropped() -> void:
	var points: Array[Vector2i] = [Vector2i(10, 0), Vector2i(30, 0), Vector2i(50, 0)]
	var players: Array[Vector2] = [ \
		Iso.to_screen(Vector2i(50, 0)) + Vector2(100.0, 0.0), \
		Iso.to_screen(Vector2i(30, 0))]
	var kept: Array[Vector2i] = SpawnDirector.safe_cells(points, players, \
		SpawnDirector.SAFE_RADIUS)
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
	assert_false(SpawnDirector.safe_cells(points, just_inside, SpawnDirector.SAFE_RADIUS) \
		.has(cell), "just inside the radius (159 px) is dropped")
	assert_true(SpawnDirector.safe_cells(points, exactly_at, SpawnDirector.SAFE_RADIUS) \
		.has(cell), "exactly at the radius (160 px) is kept")


func test_no_players_leaves_every_spawn_point_safe() -> void:
	var points: Array[Vector2i] = [Vector2i(10, 0), Vector2i(30, 0), Vector2i(50, 0)]
	assert_eq(SpawnDirector.safe_cells(points, [], SpawnDirector.SAFE_RADIUS), points, \
		"an empty player list drops nothing")


func test_too_few_safe_cells_still_returns_only_the_safe_ones() -> void:
	var points: Array[Vector2i] = [Vector2i(10, 0), Vector2i(11, 0), Vector2i(300, 0)]
	var players: Array[Vector2] = [Iso.to_screen(Vector2i(10, 0)), Iso.to_screen(Vector2i(11, 0))]
	var kept: Array[Vector2i] = SpawnDirector.safe_cells(points, players, \
		SpawnDirector.SAFE_RADIUS)
	assert_eq(kept, [Vector2i(300, 0)] as Array[Vector2i], \
		"one safe cell is below the minimum, but the spec's 160 px rule has no exception — " \
		+ "only the safe cell comes back, never the blocked ones")


func test_no_safe_cell_at_all_returns_an_empty_list() -> void:
	var points: Array[Vector2i] = [Vector2i(10, 0), Vector2i(11, 0)]
	var players: Array[Vector2] = [Iso.to_screen(Vector2i(10, 0)), Iso.to_screen(Vector2i(11, 0))]
	assert_eq(SpawnDirector.safe_cells(points, players, SpawnDirector.SAFE_RADIUS).size(), 0, \
		"every spawn point blocked: an empty list, so the room fields nothing")


func test_safe_cells_never_touches_the_input_array() -> void:
	var points: Array[Vector2i] = [Vector2i(10, 0), Vector2i(11, 0)]
	var players: Array[Vector2] = [Iso.to_screen(Vector2i(10, 0))]
	SpawnDirector.safe_cells(points, players, SpawnDirector.SAFE_RADIUS)
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


func test_one_fill_room_call_spawns_only_the_first_wave_and_plans_the_whole_budget() -> void:
	_wire_world()
	var room := _room(_spec(_far_points(8)))
	var spawned: Array[Enemy] = SpawnDirector.fill_room(room)
	assert_between(spawned.size(), 1, SpawnWaves.MAX_WAVE, \
		"the first wave is 1 to 3 enemies; the rest wait for the room to thin")
	assert_eq(_planned_total(room), SpawnDirector.room_budget(1), \
		"the waves together field the floor-1 budget")
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
	assert_between(spawned.size(), 1, SpawnWaves.MAX_WAVE, \
		"enough safe cells: the first wave fields 1 to 3")
	for enemy: Enemy in spawned:
		assert_gte(enemy.position.distance_to(player.position), SpawnDirector.SAFE_RADIUS, \
			"no spawn within the player-distance threshold")
		assert_true(far_screens.has(enemy.position), \
			"every spawn sat on a safe cell, never a blocked one")


func test_a_room_with_no_safe_cell_fields_an_empty_wave() -> void:
	_wire_world()
	var points: Array[Vector2i] = [Vector2i(10, 0), Vector2i(11, 0), Vector2i(12, 0), Vector2i(13, 0)]
	var player: Player = _add_player(1, Iso.to_screen(Vector2i(11, 0)))
	var room := _room(_spec(points))
	var spawned: Array[Enemy] = SpawnDirector.fill_room(room)
	assert_eq(spawned.size(), 0, \
		"every spawn point sits inside the safe radius: no enemy spawns at all — " \
		+ "the spec's 160 px rule has no exception, so the old fallback is gone")


func test_a_room_with_fewer_safe_cells_than_the_budget_spawns_only_on_safe_cells() -> void:
	_wire_world()
	var blocked: Array[Vector2i] = [Vector2i(10, 0), Vector2i(11, 0)]
	var safe: Array[Vector2i] = [Vector2i(60, 0)]
	var points: Array[Vector2i] = []
	points.append_array(blocked)
	points.append_array(safe)
	var player: Player = _add_player(1, Iso.to_screen(Vector2i(10, 0)))
	var room := _room(_spec(points))
	var spawned: Array[Enemy] = SpawnDirector.fill_room(room)
	var safe_screens: Array[Vector2] = []
	for cell: Vector2i in safe:
		safe_screens.append(Iso.to_screen(cell))
	assert_lt(spawned.size(), SpawnDirector.room_budget(1), \
		"one safe cell against the whole budget: the wave is cut short, not filled unsafely")
	for enemy: Enemy in spawned:
		assert_gte(enemy.position.distance_to(player.position), SpawnDirector.SAFE_RADIUS, \
			"and every spawn that did land is past the threshold")
		assert_true(safe_screens.has(enemy.position), \
			"on a safe cell, never a blocked one")


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


# --- G12b: the registered populator (the registered path reaches fill_room) ---
#
# The registration is `arm_room`, not `fill_room` itself: `arm_room` arms a
# room (connects its `activated` signal to the fill on the host only), so a
# floor does not start with every room already fighting. The proof therefore
# runs the whole registered path — register, look up through the G11b
# registry, activate the room — and counts the wave that falls out.


func _enemy_count() -> int:
	var count: int = 0
	for child: Node in _world.entities.get_children():
		if child is Enemy:
			count += 1
	return count


func test_register_populators_registers_combat_and_elite_combat_in_the_registry() -> void:
	SpawnDirector.register_populators()
	assert_eq(FloorGenerator.populator_count(FloorGenerator.RoomType.COMBAT), 1, \
		"one COMBAT entry in the G11b registry")
	assert_eq(FloorGenerator.populator_count(FloorGenerator.RoomType.ELITE_COMBAT), 1, \
		"one ELITE_COMBAT entry")
	assert_eq(FloorGenerator.populator_count(FloorGenerator.RoomType.TREASURE), 0, \
		"and no type outside the pair — TREASURE's populator is another module's")


func test_register_populators_is_idempotent_so_a_startup_recall_stays_one_entry() -> void:
	SpawnDirector.register_populators()
	SpawnDirector.register_populators()
	assert_eq(FloorGenerator.populator_count(FloorGenerator.RoomType.COMBAT), 1, \
		"the same (type, callable) twice folds to one entry, per the registry's own rule")
	assert_eq(FloorGenerator.populator_count(FloorGenerator.RoomType.ELITE_COMBAT), 1, \
		"on the elite type too")


func test_main_registers_the_populators_at_startup() -> void:
	var source := FileAccess.get_file_as_string("res://scenes/main/main.gd")
	assert_gt(source.length(), 0, "scenes/main/main.gd is readable")
	assert_true(source.contains("SpawnDirector.register_populators()"), \
		"the game calls the registration at startup (SPEC-floor-generation: each owning " \
		+ "module registers its populators at startup)")


func test_a_combat_room_looked_up_through_the_registry_fills_once_on_activation() -> void:
	_wire_world()
	SpawnDirector.register_populators()
	var room := _room(_spec(_far_points(8)))
	FloorGenerator.run_populators(room)
	assert_true(room.activated.is_connected(SpawnDirector._on_room_activated), \
		"the looked-up callable armed the room: `activated` is wired to the fill on the host")
	var before: int = _enemy_count()
	room.activated.emit(room)
	assert_between(_enemy_count() - before, 1, SpawnWaves.MAX_WAVE, \
		"one activation ran fill_room once: the first wave, 1 to 3 enemies")


func test_a_second_lookup_does_not_double_arm_the_room() -> void:
	_wire_world()
	SpawnDirector.register_populators()
	var room := _room(_spec(_far_points(8)))
	FloorGenerator.run_populators(room)
	FloorGenerator.run_populators(room)
	var before: int = _enemy_count()
	room.activated.emit(room)
	assert_between(_enemy_count() - before, 1, SpawnWaves.MAX_WAVE, \
		"a repaint re-running the registry on an armed room still fields one first wave, not two")


func test_an_elite_combat_room_looked_up_through_the_registry_fills_once_on_activation() -> void:
	_wire_world()
	SpawnDirector.register_populators()
	var room := _room(_spec(_far_points(8), 4, FloorGenerator.RoomType.ELITE_COMBAT))
	FloorGenerator.run_populators(room)
	var before: int = _enemy_count()
	room.activated.emit(room)
	var spawned_budget: int = _enemy_count() - before
	assert_between(spawned_budget, 1, SpawnWaves.MAX_WAVE, \
		"one activation on the elite room too: its first wave, 1 to 3 enemies")
	var elites: int = 0
	for child: Node in _world.entities.get_children():
		if child is Enemy and (child as Enemy).elite:
			elites += 1
	assert_gte(elites, SpawnDirector.ELITE_ROOM_BONUS_ELITES, \
		"and the elite room's own fill_room bonus elite is in the wave")


# --- SpawnDirector v2 (W4-A2 part 1): waves, the 40 % release, elite chance ---------


func _planned_total(room: Room) -> int:
	var state := room.get_meta(SpawnDirector.WAVE_STATE_META) as SpawnDirector.WaveState
	var total: int = state.spawned
	for size: int in state.waves:
		total += size
	return total


func _state(room: Room) -> SpawnDirector.WaveState:
	return room.get_meta(SpawnDirector.WAVE_STATE_META) as SpawnDirector.WaveState


func test_every_wave_is_one_to_three_and_the_plan_totals_the_budget() -> void:
	for floor_index: int in [1, 10, 30]:
		var rng := RandomNumberGenerator.new()
		rng.seed = 4242
		var budget: int = SpawnDirector.room_budget(floor_index)
		var waves: Array[int] = SpawnWaves.plan(budget, rng)
		var total: int = 0
		for size: int in waves:
			assert_between(size, 1, 3, "floor %d: a wave is 1 to 3" % floor_index)
			total += size
		assert_eq(total, budget, "floor %d: the waves total the budget" % floor_index)


func test_the_next_wave_is_due_at_forty_percent_remaining() -> void:
	assert_true(SpawnWaves.next_wave_due(4, 10), "4 of 10 alive is exactly 40 %: due")
	assert_false(SpawnWaves.next_wave_due(5, 10), "5 of 10 alive is 50 %: not yet")
	assert_true(SpawnWaves.next_wave_due(0, 3), "a cleared room releases the next wave")


func test_killing_down_to_forty_percent_releases_the_next_wave() -> void:
	_wire_world()
	var room := _room(_spec(_far_points(8)))
	var first: Array[Enemy] = SpawnDirector.fill_room(room)
	var state := _state(room)
	var waves_before: int = state.waves.size()
	assert_gt(waves_before, 0, "the plan has waves after the first")
	for enemy: Enemy in first:
		if not SpawnWaves.next_wave_due(room.enemies_alive, state.spawned):
			enemy.apply_hit(100000)
	assert_lt(state.waves.size(), waves_before, "the next wave was released")
	assert_true(state.spawned > first.size(), "its enemies spawned too")


func test_the_elite_chance_is_the_scaling_curve_without_double_elites() -> void:
	for floor_index: int in [1, 10, 30]:
		assert_almost_eq(SpawnDirector.elite_chance_for(floor_index, false), Scaling.elite_chance(floor_index), 0.0001, \
			"floor %d: the plain elite chance is Scaling.elite_chance" % floor_index)


func test_double_elites_doubles_the_elite_chance_and_caps_at_one() -> void:
	for floor_index: int in [1, 10, 30]:
		var plain: float = Scaling.elite_chance(floor_index)
		assert_almost_eq(SpawnDirector.elite_chance_for(floor_index, true), minf(plain * 2.0, 1.0), 0.0001, \
			"floor %d: Double Elites doubles it" % floor_index)
	assert_eq(SpawnDirector.elite_chance_for(30, true), minf(Scaling.elite_chance(30) * 2.0, 1.0), "capped")
	assert_true(SpawnDirector.elite_chance_for(30, true) <= 1.0, "never above certainty")


func test_the_director_rolls_double_elites_from_the_floor_modifiers() -> void:
	var seed_with: int = -1
	for run_seed: int in range(1, 2000):
		if FloorGenerator.roll_modifiers(run_seed, 30).has(FloorGenerator.FloorModifier.DOUBLE_ELITES):
			seed_with = run_seed
			break
	assert_gt(seed_with, 0, "some seed rolls Double Elites on floor 30")
	assert_true(SpawnDirector._has_double_elites(seed_with, 30), "the director reads the same roll")


func test_a_director_elite_carries_a_real_affix() -> void:
	_wire_world()
	var room := _room(_spec(_far_points(8), 4, FloorGenerator.RoomType.ELITE_COMBAT))
	var spawned: Array[Enemy] = SpawnDirector.fill_room(room)
	var elite: Enemy = null
	for enemy: Enemy in spawned:
		if enemy.elite:
			elite = enemy
			break
	assert_not_null(elite, "the elite room fields its bonus elite in the first wave")
	if elite != null:
		assert_ne(elite.affix, EliteAffix.Affix.NONE, "the director gives an elite a real affix")


# --- the 160 px rule holds for every wave, and the release threshold is exact -------


func test_a_later_wave_keeps_the_safe_radius_from_a_player_who_walked_over() -> void:
	# The player starts far from every cell, then walks onto the next wave's first
	# free cell before it is released. The wave must go elsewhere.
	_wire_world()
	var room := _room(_spec(_far_points(8)))
	var player: Player = _add_player(1, Vector2(-5000.0, -5000.0))
	var first: Array[Enemy] = SpawnDirector.fill_room(room)
	var state := _state(room)
	assert_false(state.cells.is_empty(), "free cells remain for the later waves")
	player.position = Iso.to_screen(state.cells[state.cells.size() - 1])
	for enemy: Enemy in first:
		if not SpawnWaves.next_wave_due(room.enemies_alive, state.spawned):
			enemy.apply_hit(100000)
	var later: int = 0
	for node: Node in _world.entities.get_children():
		if node is Enemy and not first.has(node):
			later += 1
			assert_gte((node as Enemy).position.distance_to(player.position), SpawnDirector.SAFE_RADIUS, \
				"a later wave's spawn is still 160 px from the walked-over player")
	assert_gt(later, 0, "a later wave was released")


func test_the_safe_radius_holds_for_every_wave_across_many_room_seeds() -> void:
	# Each room index is its own rng seed (layout_seed + index * SEED_MIX), so this
	# sweeps a spread of wave plans and cell orders. Each release is checked against
	# the player's position at that moment, not against the first wave's.
	_wire_world()
	var player: Player = _add_player(1, Vector2(-5000.0, -5000.0))
	var checked: int = 0
	for index: int in range(3, 15):
		var room := _room(_spec(_far_points(10), index))
		var first: Array[Enemy] = SpawnDirector.fill_room(room)
		var state := _state(room)
		var guard: int = 0
		while not state.waves.is_empty() and guard < 20:
			guard += 1
			if not state.cells.is_empty():
				player.position = Iso.to_screen(state.cells[state.cells.size() - 1])
			var known: Array[int] = _enemy_ids()
			for enemy: Enemy in first:
				if not enemy.health.is_dead:
					enemy.apply_hit(100000)
			first.clear()
			for node: Node in _world.entities.get_children():
				if node is Enemy and not known.has(node.get_instance_id()):
					checked += 1
					assert_gte((node as Enemy).position.distance_to(player.position), SpawnDirector.SAFE_RADIUS, \
						"room index %d: a wave released while the player stood there keeps 160 px" % index)
					first.append(node as Enemy)
	assert_gt(checked, 0, "some later-wave spawns were checked")


func _enemy_ids() -> Array[int]:
	var ids: Array[int] = []
	for node: Node in _world.entities.get_children():
		if node is Enemy:
			ids.append(node.get_instance_id())
	return ids


func test_no_wave_is_released_above_forty_percent_remaining() -> void:
	_wire_world()
	# Find a room whose first wave has at least two enemies, so one death leaves the
	# room above the 40 % line. The room index is the rng seed, so this is fixed.
	var room: Room = null
	var first: Array[Enemy] = []
	for index: int in range(3, 30):
		room = _room(_spec(_far_points(8), index))
		first = SpawnDirector.fill_room(room)
		if first.size() >= 2:
			break
	assert_gte(first.size(), 2, "a room with a first wave of two or more exists")
	var state := _state(room)
	var waves_before: int = state.waves.size()
	first[0].apply_hit(100000)
	assert_false(SpawnWaves.next_wave_due(room.enemies_alive, state.spawned), "above 40 %: not due")
	assert_eq(state.waves.size(), waves_before, "and no wave was released")
