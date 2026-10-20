extends GutTest
## Tests for the run-economy data model (SPEC-run-economy): RunState,
## RunPlayerState, RunResult and RunEndReason. Owned by run-economy.
## Covers the floor bounds 1..30, the floor -> biome derivation 1..6, the
## floor-advance threshold fields, the per-player run state, and the
## RunResult shape with its kept/lost tables.

const ALL_FLOORS: Array[int] = [
	1, 2, 3, 4, 5, 6, 7, 8, 9, 10,
	11, 12, 13, 14, 15, 16, 17, 18, 19, 20,
	21, 22, 23, 24, 25, 26, 27, 28, 29, 30,
]


func test_run_state_is_refcounted() -> void:
	var state := RunState.new(1, 1)
	assert_true(state is RefCounted, "RunState is a RefCounted value object")


func test_run_player_state_is_refcounted() -> void:
	var player := RunPlayerState.new(2)
	assert_true(player is RefCounted, "RunPlayerState is a RefCounted value object")


func test_run_result_is_refcounted() -> void:
	var result := RunResult.new()
	assert_true(result is RefCounted, "RunResult is a RefCounted value object")


func test_run_state_defaults() -> void:
	var state := RunState.new()
	assert_eq(state.seed, 0)
	assert_eq(state.floor_index, 1)
	assert_eq(state.biome_index, 1)
	assert_eq(state.shared_gold, 0)
	assert_true(state.shared_ore.is_empty())
	assert_eq(state.elites_killed, 0)
	assert_eq(state.bosses_killed, 0)
	assert_eq(state.floors_cleared, 0)
	assert_eq(state.rooms_cleared_no_hit, 0)
	assert_eq(state.rooms_cleared, 0)
	assert_eq(state.required_rooms_cleared, 0)
	assert_true(state.players.is_empty())
	assert_true(state.time_started >= 0, "time_started is a millisecond stamp")


func test_floor_index_clamps_to_1_through_30() -> void:
	assert_eq(RunState.new(1, 0).floor_index, 1, "below floor 1 clamps up")
	assert_eq(RunState.new(1, -5).floor_index, 1, "negative floors clamp up")
	assert_eq(RunState.new(1, 31).floor_index, 30, "above floor 30 clamps down")
	assert_eq(RunState.new(1, 999).floor_index, 30, "far out of range clamps down")


func test_biome_index_derives_from_floor() -> void:
	var expected: Array[int] = [1, 1, 1, 1, 1, 2, 2, 2, 2, 2, 3, 3, 3, 3, 3,
		4, 4, 4, 4, 4, 5, 5, 5, 5, 5, 6, 6, 6, 6, 6]
	for index: int in range(ALL_FLOORS.size()):
		var state := RunState.new(1, ALL_FLOORS[index])
		assert_eq(state.biome_index, expected[index],
			"floor %d maps to biome %d" % [ALL_FLOORS[index], expected[index]])


func test_biome_index_is_always_in_1_through_6() -> void:
	for floor_number: int in ALL_FLOORS:
		var state := RunState.new(1, floor_number)
		assert_between(state.biome_index, 1, 6,
			"floor %d keeps biome_index in range" % floor_number)


func test_changing_floor_recomputes_biome() -> void:
	var state := RunState.new(1, 1)
	state.floor_index = 6
	assert_eq(state.floor_index, 6)
	assert_eq(state.biome_index, 2, "floor 6 opens biome 2")
	state.floor_index = 26
	assert_eq(state.biome_index, 6, "floor 26 opens biome 6")
	state.floor_index = 0
	assert_eq(state.floor_index, 1, "assignment clamps too")
	assert_eq(state.biome_index, 1)


func test_exit_is_closed_until_required_rooms_are_cleared() -> void:
	var state := RunState.new(1, 1)
	state.required_rooms_cleared = 3
	assert_false(state.exit_open, "exit starts closed")
	assert_false(state.can_advance(), "no advance before the exit opens")
	state.rooms_cleared = 1
	assert_false(state.exit_open)
	assert_false(state.can_advance())
	state.rooms_cleared = 2
	assert_false(state.exit_open, "one room still outstanding")
	state.rooms_cleared = 3
	assert_true(state.exit_open, "exit opens when the threshold is met")
	assert_true(state.can_advance())


func test_advance_floor_moves_to_the_next_biome_floor() -> void:
	var state := RunState.new(1, 5)
	state.required_rooms_cleared = 2
	state.rooms_cleared = 2
	assert_true(state.advance_floor())
	assert_eq(state.floor_index, 6)
	assert_eq(state.biome_index, 2)
	assert_eq(state.floors_cleared, 1)
	assert_eq(state.rooms_cleared, 0, "room progress belongs to the floor left behind")
	assert_false(state.exit_open, "the next floor's exit needs its own clear")


func test_advance_floor_is_refused_while_exit_is_closed() -> void:
	var state := RunState.new(1, 1)
	state.required_rooms_cleared = 4
	assert_false(state.advance_floor())
	assert_eq(state.floor_index, 1)
	assert_eq(state.floors_cleared, 0)


func test_advance_floor_is_refused_on_floor_30() -> void:
	var state := RunState.new(1, 30)
	state.required_rooms_cleared = 1
	state.rooms_cleared = 1
	assert_false(state.advance_floor(), "floor 30 is the end of the 30-floor run")
	assert_eq(state.floor_index, 30)
	assert_eq(state.floors_cleared, 0)


func test_players_are_keyed_by_peer_id() -> void:
	var state := RunState.new(7, 1)
	var player := RunPlayerState.new(4, &"wren", &"warrior")
	state.add_player(player)
	assert_true(state.players.has(4))
	assert_eq(state.get_player(4), player)
	assert_eq(state.players[4].peer_id, 4)
	assert_null(state.get_player(99))


func test_run_player_state_defaults() -> void:
	var player := RunPlayerState.new(3)
	assert_eq(player.peer_id, 3)
	assert_true(player.weapon_ids.is_empty())
	assert_true(player.weapon_mutations.is_empty())
	assert_true(player.relics.is_empty())
	assert_true(player.abilities.is_empty())
	assert_eq(player.ascension, &"")
	assert_true(player.potions.is_empty())
	assert_eq(player.echo_shards_earned, 0)
	assert_eq(player.class_xp_earned, 0)
	assert_eq(player.gold_share, 0)
	assert_false(player.is_downed)


func test_run_player_state_holds_weapons_and_mutations() -> void:
	var player := RunPlayerState.new(2, &"ivy", &"mage")
	player.weapon_ids = [&"lantern_staff", &"pickaxe"] as Array[StringName]
	player.add_weapon(&"lantern_staff", [&"ember_bolt", &"split_beam"] as Array[StringName])
	var mutations: Array[StringName] = player.mutations_for(&"lantern_staff")
	assert_eq(mutations, [&"ember_bolt", &"split_beam"] as Array[StringName])
	assert_true(player.mutations_for(&"pickaxe").is_empty())
	assert_true(player.mutations_for(&"missing").is_empty())


func test_run_player_state_holds_relics_abilities_and_potions() -> void:
	var player := RunPlayerState.new(2, &"ivy", &"mage")
	player.relics = [&"ember_heart"] as Array[StringName]
	player.abilities = [&"fireball"] as Array[StringName]
	player.potions = [&"heal"] as Array[StringName]
	player.ascension = &"pyromancer"
	player.echo_shards_earned = 12
	player.class_xp_earned = 40
	player.gold_share = 25
	player.is_downed = true
	assert_eq(player.relics, [&"ember_heart"] as Array[StringName])
	assert_eq(player.abilities, [&"fireball"] as Array[StringName])
	assert_eq(player.potions, [&"heal"] as Array[StringName])
	assert_eq(player.ascension, &"pyromancer")
	assert_eq(player.echo_shards_earned, 12)
	assert_eq(player.class_xp_earned, 40)
	assert_eq(player.gold_share, 25)
	assert_true(player.is_downed)


func test_run_end_reason_has_the_four_spec_values() -> void:
	var values: Array = RunEndReason.Reason.values()
	assert_eq(values.size(), 4, "RunEndReason has exactly four values")
	assert_eq(values[0], RunEndReason.Reason.DEFEAT)
	assert_eq(values[1], RunEndReason.Reason.EXTRACT)
	assert_eq(values[2], RunEndReason.Reason.VICTORY)
	assert_eq(values[3], RunEndReason.Reason.ABORT)


func test_run_result_shape() -> void:
	var result := RunResult.new(RunEndReason.Reason.EXTRACT, 12345, 3)
	assert_eq(result.reason, RunEndReason.Reason.EXTRACT)
	assert_eq(result.seed, 12345)
	assert_eq(result.floors_cleared, 3)
	assert_true(result.kept.is_empty(), "no per-player tables until they are set")
	assert_true(result.lost.is_empty())


func test_run_result_kept_and_lost_tables_per_player() -> void:
	var result := RunResult.new(RunEndReason.Reason.DEFEAT, 99, 2)
	var kept: Dictionary = RunResult.empty_table()
	kept[&"gold"] = 25
	var lost: Dictionary = RunResult.empty_table()
	lost[&"gold"] = 75
	result.set_player_tables(5, kept, lost)
	assert_eq(result.kept[5][&"gold"], 25)
	assert_eq(result.lost[5][&"gold"], 75)
	assert_true(result.kept.has(5))
	assert_true(result.lost.has(5))


func test_run_result_empty_table_has_the_documented_keys() -> void:
	var table: Dictionary = RunResult.empty_table()
	for key: StringName in [&"gold", &"ore", &"relics", &"echo_shards", &"class_xp"]:
		assert_true(table.has(key), "empty_table carries the %s key" % key)
	assert_eq(table[&"gold"], 0)
	assert_eq(table[&"ore"], 0)
	assert_eq(table[&"echo_shards"], 0)
	assert_eq(table[&"class_xp"], 0)
	assert_true((table[&"relics"] as Array).is_empty())
