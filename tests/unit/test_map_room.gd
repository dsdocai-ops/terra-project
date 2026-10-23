extends GutTest
## Map Room start floors (SPEC-run-economy "Map Room shortcuts", W5-B3): which
## floors a run may start on, and the Ascension/Tier 2 timing flags the run
## carries. Pure rules (MapRoom) plus the RunState fields.


func test_rope_floors_are_floor_two_of_each_biome_and_each_boss_arena() -> void:
	assert_eq(MapRoom.rope_floors(), [2, 5, 7, 10, 12, 15, 17, 20, 22, 25, 27] as Array[int])


func test_a_floor_two_rope_starts_on_that_floor() -> void:
	assert_eq(MapRoom.start_floor_for_rope(7), 7)


func test_a_boss_arena_rope_starts_on_the_next_biomes_first_floor() -> void:
	assert_eq(MapRoom.start_floor_for_rope(5), 6)
	assert_eq(MapRoom.start_floor_for_rope(25), 26)


func test_a_non_rope_floor_has_no_start() -> void:
	assert_eq(MapRoom.start_floor_for_rope(3), 0)


func test_no_rope_reached_offers_floor_one_only() -> void:
	assert_eq(MapRoom.available_start_floors(0), [1] as Array[int])


func test_reaching_ropes_unlocks_their_start_floors() -> void:
	assert_eq(MapRoom.available_start_floors(7), [1, 2, 6, 7] as Array[int])


func test_can_start_at_only_reached_ropes() -> void:
	assert_true(MapRoom.can_start_at(6, 7))
	assert_false(MapRoom.can_start_at(12, 7), "a rope not yet reached")
	assert_false(MapRoom.can_start_at(3, 30), "floor 3 is no rope")


func test_ascension_is_picked_at_start_past_biome_one() -> void:
	assert_false(MapRoom.ascension_picked_at_start(1))
	assert_false(MapRoom.ascension_picked_at_start(5))
	assert_true(MapRoom.ascension_picked_at_start(6))


func test_tier_two_starts_past_biome_four() -> void:
	assert_false(MapRoom.starts_tier_two(20))
	assert_true(MapRoom.starts_tier_two(21))
	assert_true(MapRoom.starts_tier_two(26))


func test_run_state_records_the_start_floor_and_flags() -> void:
	var run: RunState = RunState.new(1, 12)
	assert_eq(run.start_floor, 12)
	assert_true(run.ascension_pick_at_start)
	assert_false(run.starts_tier_two)
	run.floor_index = 14
	assert_eq(run.start_floor, 12, "the start floor never moves")


func test_a_normal_run_has_no_early_flags() -> void:
	var run: RunState = RunState.new(1)
	assert_eq(run.start_floor, 1)
	assert_false(run.ascension_pick_at_start)
	assert_false(run.starts_tier_two)
