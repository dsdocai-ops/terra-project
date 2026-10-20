extends GutTest
## Tests for the all-downed run end (SPEC-run-economy, W3-B2b): the run ends
## with DEFEAT once every player is downed or dead, and the placeholder
## death/extract summary line is printed. Owned by run-economy.
##
## The rule is BRIEF Assumption 7: zero players both alive and not downed.
## Downed counts as not living, so a solo run ends on its first down.
##
## Signal values are captured with named method callbacks, never lambdas
## (LESSONS: `.connect(lambda)` never fires under GUT). Player events are driven
## from test-local Player doubles — a bare `Player.new()` with only `peer_id`
## set, which is all the run slice needs; a node that was never added to the
## tree never runs Dev A's `_ready`, so nothing in their scene is touched.
## after_each ends any run a test left live (which is what disconnects the
## Events subscriptions) and clears GameState.run / forced_seed before the
## NetworkManager session is dropped, so no autoload state leaks into the next
## file (LESSONS: autoload state bleeds across GUT files).

const FORCED_SEED: int = 4242
const HOST_PEER: int = 1
const FLOORS_CLEARED: int = 3

var _started_seeds: Array[int] = []
var _ended_results: Array[RunResult] = []
## Player doubles to free in after_each; they are never added to the tree.
var _doubles: Array[Player] = []
## Peer ids whose player_downed / player_died the tests have already emitted.
var _reentrant_end_requested: bool = false


func before_each() -> void:
	GameState.run = null
	GameState.forced_seed = 0
	GameState.last_run_summary = ""
	_started_seeds.clear()
	_ended_results.clear()
	_reentrant_end_requested = false
	GameState.run_started.connect(_record_run_started)
	GameState.run_ended.connect(_record_run_ended)


func after_each() -> void:
	if GameState.run_started.is_connected(_record_run_started):
		GameState.run_started.disconnect(_record_run_started)
	if GameState.run_ended.is_connected(_record_run_ended):
		GameState.run_ended.disconnect(_record_run_ended)
	# A live run holds the Events subscriptions open; ending it is also what a
	# real quit does, so cleanup uses the public path rather than poking at
	# private handlers.
	if GameState.run != null and NetworkManager.is_host:
		GameState.end_run(RunEndReason.Reason.ABORT)
	for double: Player in _doubles:
		double.free()
	_doubles.clear()
	GameState.run = null
	GameState.forced_seed = 0
	GameState.last_run_summary = ""
	NetworkManager.disconnect_all()


func _record_run_started(run_seed: int) -> void:
	_started_seeds.append(run_seed)


## Also proves the re-entry guard: a listener that ends the run from inside
## run_ended must not produce a second run_ended.
func _record_run_ended(result: RefCounted) -> void:
	if _reentrant_end_requested:
		_reentrant_end_requested = false
		GameState.end_run(RunEndReason.Reason.ABORT)
	var typed: RunResult = result as RunResult
	if typed != null:
		_ended_results.append(typed)


## A solo session is a host with one peer — the same code path co-op uses.
func _become_host() -> void:
	NetworkManager.start_solo()
	assert_true(NetworkManager.is_host, "test session is a host")


## A test-local double for Dev A's Player: nothing is read from it but the
## peer id, and it never enters the tree.
func _player(peer_id: int) -> Player:
	var double: Player = Player.new()
	double.peer_id = peer_id
	_doubles.append(double)
	return double


func _party(peer_ids: Array[int]) -> Array[PlayerSpawnInfo]:
	var party: Array[PlayerSpawnInfo] = []
	for peer_id: int in peer_ids:
		party.append(PlayerSpawnInfo.new(peer_id))
	return party


## Starts a host run for the given peers with the forced seed, so every test
## run is reproducible.
func _start_run(peer_ids: Array[int], run_seed: int = FORCED_SEED) -> void:
	_become_host()
	GameState.forced_seed = run_seed
	GameState.start_run(0, 1, _party(peer_ids))


## Drives SPEC-player-controller's downed event for a peer.
func _down(peer_id: int) -> void:
	Events.player_downed.emit(_player(peer_id))


## Drives SPEC-player-controller's death event for a peer.
func _die(peer_id: int) -> void:
	Events.player_died.emit(_player(peer_id))


func _slice(peer_id: int) -> RunPlayerState:
	return GameState.run.get_player(peer_id)


# --- the all-downed rule ---------------------------------------------------


func test_a_solo_run_ends_with_defeat_on_the_first_down() -> void:
	_start_run([HOST_PEER])
	_down(HOST_PEER)
	assert_eq(_ended_results.size(), 1, "the only player going down ends the run")
	assert_eq(_ended_results[0].reason, RunEndReason.Reason.DEFEAT)
	assert_null(GameState.run, "the run is over")


func test_a_solo_run_ends_with_defeat_on_death() -> void:
	_start_run([HOST_PEER])
	_die(HOST_PEER)
	assert_eq(_ended_results.size(), 1, "a dead solo player ends the run")
	assert_eq(_ended_results[0].reason, RunEndReason.Reason.DEFEAT)


func test_two_players_with_one_downed_keep_the_run_alive() -> void:
	_start_run([1, 2])
	_down(1)
	assert_true(_ended_results.is_empty(), "one player still stands")
	assert_not_null(GameState.run, "the run continues")
	assert_true(_slice(1).is_downed, "the downed player is marked in the run slice")
	assert_true(_slice(2).is_standing(), "the other player still stands")


func test_the_second_down_ends_the_run_with_defeat() -> void:
	_start_run([1, 2])
	_down(1)
	_down(2)
	assert_eq(_ended_results.size(), 1, "the last standing player going down ends the run")
	assert_eq(_ended_results[0].reason, RunEndReason.Reason.DEFEAT)
	assert_null(GameState.run, "the run is over")
	assert_true(_ended_results[0].kept.has(1), "each player still gets a kept table")
	assert_true(_ended_results[0].kept.has(2))


func test_four_players_end_only_when_the_last_one_goes_down() -> void:
	_start_run([1, 2, 3, 4])
	_down(1)
	_down(3)
	assert_true(_ended_results.is_empty(), "three of four still stand")
	_down(2)
	assert_true(_ended_results.is_empty(), "two of four still stand")
	_down(4)
	assert_eq(_ended_results.size(), 1, "the fourth down ends the run")
	assert_eq(_ended_results[0].reason, RunEndReason.Reason.DEFEAT)


func test_a_dead_player_is_not_standing() -> void:
	_start_run([1, 2])
	_die(2)
	assert_true(_ended_results.is_empty(), "a dead player is not standing, but peer 1 is")
	assert_false(_slice(2).is_standing(), "death leaves nobody standing behind it")
	assert_true(_slice(1).is_standing())
	_down(1)
	assert_eq(_ended_results.size(), 1, "the second player going down ends the run")


func test_a_dead_player_alongside_a_downed_player_ends_the_run() -> void:
	_start_run([1, 2])
	_die(1)
	_down(2)
	assert_eq(_ended_results.size(), 1, "downed and dead both count as not standing")
	assert_eq(_ended_results[0].reason, RunEndReason.Reason.DEFEAT)


func test_a_player_downed_then_dead_ends_the_run_once() -> void:
	_start_run([HOST_PEER])
	_down(HOST_PEER)
	_die(HOST_PEER)
	assert_eq(_ended_results.size(), 1, "the run was already over when the death arrived")
	assert_eq(_ended_results[0].reason, RunEndReason.Reason.DEFEAT)


# --- guards ----------------------------------------------------------------


func test_a_client_never_ends_the_run_on_a_down() -> void:
	_start_run([1, 2])
	NetworkManager.is_host = false
	_down(1)
	_down(2)
	assert_true(_ended_results.is_empty(), "clients never decide a run end")
	assert_not_null(GameState.run, "the run survives a client-side down")


func test_a_repeated_down_for_the_same_player_does_not_stand_in_for_a_second_loss() -> void:
	_start_run([1, 2])
	_down(1)
	_down(1)
	assert_true(_ended_results.is_empty(), "a duplicate event is not a second player going down")
	_down(2)
	assert_eq(_ended_results.size(), 1, "the run still ends when the real last player goes down")


func test_a_down_for_a_peer_outside_the_run_is_ignored() -> void:
	_start_run([1, 2])
	_down(7)
	assert_true(_ended_results.is_empty(), "a peer that is not in the run cannot end it")
	assert_false(_slice(1).is_downed, "no other player is marked")
	assert_false(_slice(2).is_downed)


func test_a_down_without_a_live_run_is_ignored() -> void:
	_become_host()
	assert_null(GameState.run)
	_down(HOST_PEER)
	assert_true(_ended_results.is_empty(), "there is no run to end")
	pass_test("a downed event with no run live is a no-op")


func test_end_run_stops_listening_to_player_events() -> void:
	_start_run([1, 2])
	var finished: RunState = GameState.run
	GameState.end_run(RunEndReason.Reason.EXTRACT)
	_down(1)
	_down(2)
	assert_eq(_ended_results.size(), 1, "an ended run is not ended again by a later down")
	assert_false(finished.get_player(1).is_downed, "an ended run stops recording events")


func test_run_ended_fires_exactly_once_when_a_listener_ends_the_run_again() -> void:
	_start_run([HOST_PEER])
	_reentrant_end_requested = true
	_down(HOST_PEER)
	assert_eq(_ended_results.size(), 1, "a re-entrant end_run has no run left to end")
	assert_eq(_started_seeds.size(), 1)


func test_the_events_bus_run_ended_fires_once_on_defeat() -> void:
	_start_run([HOST_PEER])
	watch_signals(Events)
	_down(HOST_PEER)
	assert_signal_emit_count(Events, "run_ended", 1)


# --- run slice bookkeeping -------------------------------------------------


func test_a_down_marks_the_run_slice_and_nothing_else() -> void:
	_start_run([1, 2])
	_down(1)
	assert_true(_slice(1).is_downed, "the run records which player is down")
	assert_false(_slice(1).is_dead, "a down is not a death")
	assert_false(_slice(2).is_downed, "only the named player is marked")


func test_a_death_marks_the_run_slice_dead() -> void:
	_start_run([1, 2])
	_die(1)
	assert_true(_slice(1).is_dead, "the run records which player died")
	assert_false(_slice(1).is_standing(), "a dead player does not stand")


# --- the placeholder summary ----------------------------------------------


func test_the_defeat_summary_names_the_reason_seed_and_floors_cleared() -> void:
	_start_run([HOST_PEER])
	GameState.run.floors_cleared = FLOORS_CLEARED
	_down(HOST_PEER)
	var summary: String = GameState.last_run_summary
	assert_string_contains(summary, "DEFEAT", "the summary names the reason")
	assert_string_contains(summary, "seed %d" % FORCED_SEED, "the summary names the run seed")
	assert_string_contains(summary, "floors cleared %d" % FLOORS_CLEARED,
		"the summary names how far the party got")


func test_the_summary_lists_every_players_status() -> void:
	_start_run([1, 2])
	GameState.run.floors_cleared = FLOORS_CLEARED
	_down(1)
	_down(2)
	var summary: String = GameState.last_run_summary
	assert_string_contains(summary, "1 downed", "a downed player is listed as downed")
	assert_string_contains(summary, "2 downed", "every player is listed")


func test_the_summary_distinguishes_a_dead_player_from_a_downed_one() -> void:
	_start_run([1, 2])
	_die(1)
	_down(2)
	var summary: String = GameState.last_run_summary
	assert_string_contains(summary, "1 dead", "a dead player is listed as dead")
	assert_string_contains(summary, "2 downed", "a downed player is listed as downed")


func test_the_extract_summary_uses_the_same_line() -> void:
	_start_run([HOST_PEER])
	GameState.run.floors_cleared = FLOORS_CLEARED
	GameState.end_run(RunEndReason.Reason.EXTRACT)
	assert_string_contains(GameState.last_run_summary, "EXTRACT",
		"the summary line is the death/extract placeholder, not a defeat-only print")
	assert_string_contains(GameState.last_run_summary, "floors cleared %d" % FLOORS_CLEARED)


func test_the_defeat_result_matches_the_run_at_the_moment_it_ended() -> void:
	_start_run([1, 2])
	GameState.run.floors_cleared = FLOORS_CLEARED
	_down(1)
	_down(2)
	assert_eq(_ended_results.size(), 1)
	assert_eq(_ended_results[0].reason, RunEndReason.Reason.DEFEAT)
	assert_eq(_ended_results[0].seed, FORCED_SEED)
	assert_eq(_ended_results[0].floors_cleared, FLOORS_CLEARED,
		"the result is built from the run's final state")
