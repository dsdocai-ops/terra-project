extends GutTest
## Tests for the real GameState run lifecycle (SPEC-run-economy, W3-B1b):
## start_run / next_floor / end_run and the run_started / floor_changed /
## run_ended signals, the host-only refusals, the --seed (forced_seed) and
## host-roll plumbing, and the RunResult handed to run_ended.
## Owned by run-economy.
##
## Signal values are captured with named method callbacks, never lambdas
## (LESSONS: `.connect(lambda)` never fires under GUT). after_each clears
## GameState.run, GameState.forced_seed and the NetworkManager session so no
## autoload state leaks into the next test file (LESSONS: autoload state
## bleeds across GUT files).

const FORCED_SEED: int = 4242
## Floor 6 is the first floor of biome 2, so an advance to it proves the biome
## is recomputed rather than reused.
const BIOME_2_FLOOR: int = 6

var _started_seeds: Array[int] = []
## (floor_index, biome_id) pairs from floor_changed.
var _floor_events: Array[Vector2i] = []
var _ended_results: Array[RunResult] = []


func before_each() -> void:
	GameState.run = null
	GameState.forced_seed = 0
	_started_seeds.clear()
	_floor_events.clear()
	_ended_results.clear()
	GameState.run_started.connect(_record_run_started)
	GameState.floor_changed.connect(_record_floor_changed)
	GameState.run_ended.connect(_record_run_ended)


func after_each() -> void:
	if GameState.run_started.is_connected(_record_run_started):
		GameState.run_started.disconnect(_record_run_started)
	if GameState.floor_changed.is_connected(_record_floor_changed):
		GameState.floor_changed.disconnect(_record_floor_changed)
	if GameState.run_ended.is_connected(_record_run_ended):
		GameState.run_ended.disconnect(_record_run_ended)
	GameState.run = null
	GameState.forced_seed = 0
	NetworkManager.disconnect_all()


func _record_run_started(run_seed: int) -> void:
	_started_seeds.append(run_seed)


func _record_floor_changed(floor_index: int, biome: Resource) -> void:
	var placeholder: BiomePlaceholder = biome as BiomePlaceholder
	var biome_id: int = placeholder.id if placeholder != null else 0
	_floor_events.append(Vector2i(floor_index, biome_id))


func _record_run_ended(result: RefCounted) -> void:
	var typed: RunResult = result as RunResult
	if typed != null:
		_ended_results.append(typed)


## A solo session is a host with one peer — the same code path co-op uses.
func _become_host() -> void:
	NetworkManager.start_solo()
	assert_true(NetworkManager.is_host, "test session is a host")


func _party(peer_ids: Array[int]) -> Array[PlayerSpawnInfo]:
	var party: Array[PlayerSpawnInfo] = []
	for peer_id: int in peer_ids:
		party.append(PlayerSpawnInfo.new(peer_id))
	return party


func test_start_run_is_refused_on_a_client() -> void:
	GameState.forced_seed = FORCED_SEED
	GameState.start_run(0, 1, _party([1]))
	assert_null(GameState.run, "a client never owns run state")
	assert_eq(_started_seeds, [] as Array[int], "no run_started on a client")


func test_start_run_builds_a_run_state_at_the_start_floor() -> void:
	_become_host()
	GameState.forced_seed = FORCED_SEED
	GameState.start_run(0, 7, _party([1, 2]))
	assert_not_null(GameState.run, "the host owns the live run")
	assert_eq(GameState.run.seed, FORCED_SEED)
	assert_eq(GameState.run.floor_index, 7, "the run starts at start_floor")
	assert_eq(GameState.run.biome_index, 2, "floor 7 is biome 2")
	assert_eq(_started_seeds, [FORCED_SEED] as Array[int], "run_started carries the run seed")


func test_start_run_uses_forced_seed_verbatim() -> void:
	_become_host()
	GameState.forced_seed = FORCED_SEED
	GameState.start_run(987, 1, _party([1]))
	assert_eq(GameState.run.seed, FORCED_SEED, "--seed wins over an explicit seed")
	assert_eq(_started_seeds, [FORCED_SEED] as Array[int])


func test_start_run_honours_an_explicit_seed_when_none_is_forced() -> void:
	_become_host()
	GameState.forced_seed = 0
	GameState.start_run(987, 1, _party([1]))
	assert_eq(GameState.run.seed, 987, "an explicit caller seed is used when no --seed was given")


func test_start_run_rolls_a_nonzero_host_seed_when_none_is_forced() -> void:
	_become_host()
	GameState.forced_seed = 0
	GameState.start_run(0, 1, _party([1]))
	assert_not_null(GameState.run)
	assert_ne(GameState.run.seed, 0, "the host rolled a real seed")
	assert_eq(_started_seeds, [GameState.run.seed] as Array[int],
		"run_started carries the exact seed the run was built with")


func test_start_run_copies_the_party_into_run_player_slices() -> void:
	_become_host()
	var party: Array[PlayerSpawnInfo] = [
		PlayerSpawnInfo.new(1, &"wren", &"warrior", [&"pickaxe", &"crossbow"] as Array[StringName]),
		PlayerSpawnInfo.new(2, &"ivy", &"mage"),
	]
	GameState.start_run(11, 1, party)
	assert_eq(GameState.run.players.size(), 2, "one slice per party member")
	var first: RunPlayerState = GameState.run.get_player(1)
	assert_not_null(first)
	assert_eq(first.character_id, &"wren")
	assert_eq(first.class_id, &"warrior")
	assert_eq(first.weapon_ids, [&"pickaxe", &"crossbow"] as Array[StringName])
	var second: RunPlayerState = GameState.run.get_player(2)
	assert_not_null(second)
	assert_eq(second.character_id, &"ivy")
	assert_eq(second.weapon_ids, PlayerSpawnInfo.DEFAULT_WEAPONS, "the party's default loadout is kept")


func test_start_run_replaces_a_live_run() -> void:
	_become_host()
	GameState.start_run(1, 1, _party([1]))
	GameState.start_run(2, 4, _party([1, 2]))
	assert_eq(GameState.run.seed, 2, "the newest run is the live one")
	assert_eq(GameState.run.floor_index, 4)
	assert_eq(_started_seeds, [1, 2] as Array[int], "each start_run announces itself")


func test_next_floor_emits_floor_changed_with_the_biome() -> void:
	_become_host()
	GameState.start_run(5, BIOME_2_FLOOR - 1, _party([1]))
	GameState.next_floor()
	assert_eq(GameState.run.floor_index, BIOME_2_FLOOR)
	assert_eq(GameState.run.biome_index, 2)
	assert_eq(_floor_events, [Vector2i(BIOME_2_FLOOR, 2)] as Array[Vector2i],
		"floor_changed carries the new floor and its biome")


func test_next_floor_increments_once_per_call() -> void:
	_become_host()
	GameState.start_run(5, 1, _party([1]))
	GameState.next_floor()
	GameState.next_floor()
	assert_eq(GameState.run.floor_index, 3)
	assert_eq(_floor_events, [Vector2i(2, 1), Vector2i(3, 1)] as Array[Vector2i])


func test_next_floor_is_refused_past_floor_30() -> void:
	_become_host()
	GameState.start_run(5, RunState.MAX_FLOOR, _party([1]))
	GameState.next_floor()
	assert_eq(GameState.run.floor_index, RunState.MAX_FLOOR, "floor 30 is the end of the run")
	assert_true(_floor_events.is_empty(), "no floor_changed beyond the last floor")


func test_next_floor_is_refused_on_a_client() -> void:
	_become_host()
	GameState.start_run(5, 1, _party([1]))
	NetworkManager.is_host = false
	GameState.next_floor()
	assert_eq(GameState.run.floor_index, 1, "clients never advance the floor")
	assert_true(_floor_events.is_empty())


func test_end_run_emits_run_ended_once_with_the_result_and_clears_the_run() -> void:
	_become_host()
	GameState.start_run(5, 3, _party([1, 2]))
	GameState.run.floors_cleared = 2
	GameState.end_run(RunEndReason.Reason.EXTRACT)
	assert_eq(_ended_results.size(), 1, "run_ended fires exactly once")
	var result: RunResult = _ended_results[0]
	assert_eq(result.reason, RunEndReason.Reason.EXTRACT)
	assert_eq(result.seed, 5)
	assert_eq(result.floors_cleared, 2)
	assert_true(result.kept.has(1), "every player gets a kept table")
	assert_true(result.kept.has(2))
	assert_true(result.lost.has(1), "every player gets a lost table")
	assert_true(result.lost.has(2))
	assert_null(GameState.run, "end_run clears the live run")


func test_end_run_twice_fires_run_ended_once() -> void:
	_become_host()
	GameState.start_run(5, 1, _party([1]))
	GameState.end_run(RunEndReason.Reason.DEFEAT)
	GameState.end_run(RunEndReason.Reason.DEFEAT)
	assert_eq(_ended_results.size(), 1, "the second end_run has no run left to end")


func test_end_run_is_refused_without_a_live_run() -> void:
	_become_host()
	assert_null(GameState.run)
	GameState.end_run(RunEndReason.Reason.ABORT)
	assert_true(_ended_results.is_empty(), "ending a run that does not exist does nothing")


func test_end_run_is_refused_on_a_client() -> void:
	_become_host()
	GameState.start_run(5, 1, _party([1]))
	NetworkManager.is_host = false
	GameState.end_run(RunEndReason.Reason.VICTORY)
	assert_true(_ended_results.is_empty(), "clients never end the run")
	assert_not_null(GameState.run, "the run survives a client's end_run")


func test_run_lifecycle_also_emits_the_events_bus_signals() -> void:
	_become_host()
	watch_signals(Events)
	GameState.start_run(31, 1, _party([1]))
	assert_signal_emitted_with_parameters(Events, "run_started", [31])
	GameState.end_run(RunEndReason.Reason.ABORT)
	assert_signal_emit_count(Events, "run_ended", 1)


func test_request_extract_vote_stays_a_week_5_placeholder() -> void:
	_become_host()
	GameState.start_run(5, 1, _party([1, 2]))
	GameState.request_extract_vote(2, true)
	assert_not_null(GameState.run, "the rope vote path lands in week 5")
	assert_true(_ended_results.is_empty(), "a vote never ends the run yet")


func test_request_extract_vote_is_refused_on_a_client() -> void:
	GameState.request_extract_vote(1, true)
	assert_null(GameState.run, "votes are applied on the host, never locally")
