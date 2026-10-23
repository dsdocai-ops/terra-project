extends GutTest
## Tests for the death and extraction table (SPEC-run-economy, W5-B2): every
## currency for both run endings, with and without Deep Pockets, Ore Heart and
## Safe Line, and the co-op split. Owned by run-economy.
## The rules are pure (RunEconomyRules.settle), so these tests build a RunState
## by hand and never touch GameState or the network.

const RULES_SEED: int = 31337


func _run(peer_ids: Array[int]) -> RunState:
	var run: RunState = RunState.new(RULES_SEED, 1)
	for peer_id: int in peer_ids:
		run.add_player(RunPlayerState.new(peer_id))
	return run


func _settle(
	reason: RunEndReason.Reason,
	run: RunState,
	ranks: Dictionary[int, Dictionary] = {},
) -> RunResult:
	var result: RunResult = RunResult.new(reason, run.seed, 0)
	RunEconomyRules.settle(result, run, ranks)
	return result


func _solo(gold: int = 0) -> RunState:
	var run: RunState = _run([1])
	run.shared_gold = gold
	return run


# --- gold ------------------------------------------------------------------


func test_extract_keeps_all_gold() -> void:
	var result: RunResult = _settle(RunEndReason.Reason.EXTRACT, _solo(200))
	assert_eq(result.kept[1][&"gold"], 200)
	assert_eq(result.lost[1][&"gold"], 0)


func test_victory_keeps_all_gold() -> void:
	var result: RunResult = _settle(RunEndReason.Reason.VICTORY, _solo(200))
	assert_eq(result.kept[1][&"gold"], 200)


func test_death_keeps_a_quarter_of_the_gold() -> void:
	var result: RunResult = _settle(RunEndReason.Reason.DEFEAT, _solo(200))
	assert_eq(result.kept[1][&"gold"], 50)
	assert_eq(result.lost[1][&"gold"], 150)


func test_abort_counts_as_death() -> void:
	var result: RunResult = _settle(RunEndReason.Reason.ABORT, _solo(200))
	assert_eq(result.kept[1][&"gold"], 50, "a quit mid-run is a death")


func test_deep_pockets_adds_ten_percent_per_rank_on_death() -> void:
	for rank: int in [1, 2, 3]:
		var ranks: Dictionary[int, Dictionary] = {1: {&"deep_pockets": rank}}
		var result: RunResult = _settle(RunEndReason.Reason.DEFEAT, _solo(200), ranks)
		assert_eq(result.kept[1][&"gold"], 200 * (25 + 10 * rank) / 100, "rank %d" % rank)


func test_deep_pockets_changes_nothing_on_extract() -> void:
	var ranks: Dictionary[int, Dictionary] = {1: {&"deep_pockets": 3}}
	var result: RunResult = _settle(RunEndReason.Reason.EXTRACT, _solo(200), ranks)
	assert_eq(result.kept[1][&"gold"], 200)


func test_gold_kept_plus_lost_is_the_share() -> void:
	var result: RunResult = _settle(RunEndReason.Reason.DEFEAT, _solo(101))
	assert_eq(result.kept[1][&"gold"] + result.lost[1][&"gold"], 101)


# --- ore -------------------------------------------------------------------


func _ore_run() -> RunState:
	var run: RunState = _solo()
	run.shared_ore = {&"copper": 10, &"iron": 4}
	return run


func test_extract_keeps_all_ore() -> void:
	var result: RunResult = _settle(RunEndReason.Reason.EXTRACT, _ore_run())
	assert_eq(result.kept[1][&"ore"][&"copper"], 10)
	assert_eq(result.kept[1][&"ore"][&"iron"], 4)
	assert_eq(result.lost[1][&"ore"][&"copper"], 0)


func test_death_loses_all_ore() -> void:
	var result: RunResult = _settle(RunEndReason.Reason.DEFEAT, _ore_run())
	assert_eq(result.kept[1][&"ore"][&"copper"], 0)
	assert_eq(result.lost[1][&"ore"][&"copper"], 10)
	assert_eq(result.lost[1][&"ore"][&"iron"], 4)


func test_ore_heart_keeps_half_the_ore_on_death() -> void:
	var ranks: Dictionary[int, Dictionary] = {1: {&"ore_heart": 1}}
	var result: RunResult = _settle(RunEndReason.Reason.DEFEAT, _ore_run(), ranks)
	assert_eq(result.kept[1][&"ore"][&"copper"], 5)
	assert_eq(result.lost[1][&"ore"][&"copper"], 5)
	assert_eq(result.kept[1][&"ore"][&"iron"], 2)


func test_ore_heart_changes_nothing_on_extract() -> void:
	var ranks: Dictionary[int, Dictionary] = {1: {&"ore_heart": 1}}
	var result: RunResult = _settle(RunEndReason.Reason.EXTRACT, _ore_run(), ranks)
	assert_eq(result.kept[1][&"ore"][&"copper"], 10)


# --- relics ----------------------------------------------------------------


func _relic_run() -> RunState:
	var run: RunState = _solo()
	var slice: RunPlayerState = run.get_player(1)
	slice.relics = [&"glass_cannon", &"iron_heart", &"lucky_coin"]
	return run


func test_extract_loses_every_relic() -> void:
	var result: RunResult = _settle(RunEndReason.Reason.EXTRACT, _relic_run())
	assert_true((result.kept[1][&"relics"] as Array).is_empty())
	assert_eq((result.lost[1][&"relics"] as Array).size(), 3)


func test_death_loses_every_relic_even_with_safe_line() -> void:
	var ranks: Dictionary[int, Dictionary] = {1: {&"safe_line": 1}}
	var result: RunResult = _settle(RunEndReason.Reason.DEFEAT, _relic_run(), ranks)
	assert_true((result.kept[1][&"relics"] as Array).is_empty(), "Safe Line is an extract perk")
	assert_eq((result.lost[1][&"relics"] as Array).size(), 3)


func test_safe_line_keeps_one_relic_on_extract() -> void:
	var ranks: Dictionary[int, Dictionary] = {1: {&"safe_line": 1}}
	var result: RunResult = _settle(RunEndReason.Reason.EXTRACT, _relic_run(), ranks)
	var kept: Array = result.kept[1][&"relics"]
	var lost: Array = result.lost[1][&"relics"]
	assert_eq(kept.size(), 1, "exactly one relic survives")
	assert_eq(lost.size(), 2)
	assert_false(lost.has(kept[0]), "a relic is kept or lost, never both")


func test_safe_line_pick_is_deterministic_for_a_run() -> void:
	var ranks: Dictionary[int, Dictionary] = {1: {&"safe_line": 1}}
	var first: RunResult = _settle(RunEndReason.Reason.EXTRACT, _relic_run(), ranks)
	var second: RunResult = _settle(RunEndReason.Reason.EXTRACT, _relic_run(), ranks)
	assert_eq(first.kept[1][&"relics"], second.kept[1][&"relics"])


func test_safe_line_with_no_relics_keeps_nothing() -> void:
	var ranks: Dictionary[int, Dictionary] = {1: {&"safe_line": 1}}
	var result: RunResult = _settle(RunEndReason.Reason.EXTRACT, _solo(), ranks)
	assert_true((result.kept[1][&"relics"] as Array).is_empty())


# --- echo shards, class xp --------------------------------------------------


func test_echo_shards_and_class_xp_are_kept_on_both_endings() -> void:
	for reason: RunEndReason.Reason in [
		RunEndReason.Reason.EXTRACT,
		RunEndReason.Reason.VICTORY,
		RunEndReason.Reason.DEFEAT,
		RunEndReason.Reason.ABORT,
	]:
		var run: RunState = _solo()
		run.get_player(1).echo_shards_earned = 12
		run.get_player(1).class_xp_earned = 340
		var result: RunResult = _settle(reason, run)
		assert_eq(result.kept[1][&"echo_shards"], 12, "echo shards, reason %d" % reason)
		assert_eq(result.kept[1][&"class_xp"], 340, "class xp, reason %d" % reason)
		assert_eq(result.lost[1][&"echo_shards"], 0)
		assert_eq(result.lost[1][&"class_xp"], 0)


func test_echo_shards_are_per_player() -> void:
	var run: RunState = _run([1, 2])
	run.get_player(1).echo_shards_earned = 3
	run.get_player(2).echo_shards_earned = 9
	var result: RunResult = _settle(RunEndReason.Reason.DEFEAT, run)
	assert_eq(result.kept[1][&"echo_shards"], 3)
	assert_eq(result.kept[2][&"echo_shards"], 9)


# --- co-op split ------------------------------------------------------------


func test_co_op_extract_splits_shared_pools_evenly() -> void:
	var run: RunState = _run([1, 2])
	run.shared_gold = 100
	run.shared_ore = {&"copper": 6}
	var result: RunResult = _settle(RunEndReason.Reason.EXTRACT, run)
	for peer_id: int in [1, 2]:
		assert_eq(result.kept[peer_id][&"gold"], 50)
		assert_eq(result.kept[peer_id][&"ore"][&"copper"], 3)


func test_co_op_death_applies_the_rule_then_splits() -> void:
	var run: RunState = _run([1, 2])
	run.shared_gold = 200
	run.shared_ore = {&"copper": 8}
	var result: RunResult = _settle(RunEndReason.Reason.DEFEAT, run)
	for peer_id: int in [1, 2]:
		assert_eq(result.kept[peer_id][&"gold"], 25, "25%% of 200 is 50, split in two")
		assert_eq(result.kept[peer_id][&"ore"][&"copper"], 0)
		assert_eq(result.lost[peer_id][&"ore"][&"copper"], 4)


func test_co_op_split_drops_the_remainder() -> void:
	var run: RunState = _run([1, 2])
	run.shared_gold = 3
	var result: RunResult = _settle(RunEndReason.Reason.EXTRACT, run)
	assert_eq(result.kept[1][&"gold"], 1)
	assert_eq(result.kept[2][&"gold"], 1, "3 gold between 2 players banks 1 + 1")


func test_co_op_ranks_apply_to_each_players_own_share() -> void:
	var run: RunState = _run([1, 2])
	run.shared_gold = 200
	var ranks: Dictionary[int, Dictionary] = {1: {&"deep_pockets": 3}}
	var result: RunResult = _settle(RunEndReason.Reason.DEFEAT, run, ranks)
	assert_eq(result.kept[1][&"gold"], 55, "100 share at 55%")
	assert_eq(result.kept[2][&"gold"], 25, "100 share at 25%")


func test_every_player_gets_both_tables() -> void:
	var result: RunResult = _settle(RunEndReason.Reason.EXTRACT, _run([1, 2, 3]))
	for peer_id: int in [1, 2, 3]:
		assert_true(result.kept.has(peer_id))
		assert_true(result.lost.has(peer_id))


var _end_results: Array[RunResult] = []


func _record_end(result: RefCounted) -> void:
	_end_results.append(result as RunResult)


func test_end_run_populates_the_tables_through_game_state() -> void:
	NetworkManager.start_solo()
	var party: Array[PlayerSpawnInfo] = [PlayerSpawnInfo.new(1)]
	GameState.start_run(5, 1, party)
	GameState.run.shared_gold = 80
	GameState.run.get_player(1).echo_shards_earned = 4
	_end_results.clear()
	GameState.run_ended.connect(_record_end)
	GameState.end_run(RunEndReason.Reason.DEFEAT)
	GameState.run_ended.disconnect(_record_end)
	GameState.last_run_summary = ""
	NetworkManager.disconnect_all()
	assert_eq(_end_results.size(), 1)
	assert_eq(_end_results[0].kept[1][&"gold"], 20, "25% of 80")
	assert_eq(_end_results[0].lost[1][&"gold"], 60)
	assert_eq(_end_results[0].kept[1][&"echo_shards"], 4)
