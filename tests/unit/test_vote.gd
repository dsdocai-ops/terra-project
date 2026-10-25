extends GutTest
## Tests for the rope extraction vote (SPEC-run-economy "Rope points", W5-B2):
## every living player must vote yes, downed players are excluded, a `no`
## cancels and leaves the rope usable, and a solo run extracts immediately.
## Owned by run-economy. Votes enter through GameState.request_extract_vote,
## the host-side tally that NetworkManager.request_vote_rope forwards to.
##
## Signal values are captured with named method callbacks, never lambdas
## (LESSONS: `.connect(lambda)` never fires under GUT). Player slices are
## flagged directly on the run, so no Player node is needed.

const FORCED_SEED: int = 777

var _ended_results: Array[RunResult] = []
var _vote_broadcasts: Array[Dictionary] = []


func before_each() -> void:
	GameState.run = null
	GameState.forced_seed = 0
	_ended_results.clear()
	_vote_broadcasts.clear()
	GameState.run_ended.connect(_record_run_ended)
	Events.rope_vote_updated.connect(_record_vote)


func after_each() -> void:
	if GameState.run_ended.is_connected(_record_run_ended):
		GameState.run_ended.disconnect(_record_run_ended)
	if Events.rope_vote_updated.is_connected(_record_vote):
		Events.rope_vote_updated.disconnect(_record_vote)
	if GameState.run != null and NetworkManager.is_host:
		GameState.end_run(RunEndReason.Reason.ABORT)
	GameState.run = null
	GameState.forced_seed = 0
	GameState.last_run_summary = ""
	NetworkManager.disconnect_all()


func _record_run_ended(result: RefCounted) -> void:
	var typed: RunResult = result as RunResult
	if typed != null:
		_ended_results.append(typed)


func _record_vote(votes: Dictionary) -> void:
	_vote_broadcasts.append(votes.duplicate())


func _start_run(peer_ids: Array[int]) -> void:
	NetworkManager.start_solo()
	GameState.forced_seed = FORCED_SEED
	var party: Array[PlayerSpawnInfo] = []
	for peer_id: int in peer_ids:
		party.append(PlayerSpawnInfo.new(peer_id))
	GameState.start_run(0, 1, party)


func _slice(peer_id: int) -> RunPlayerState:
	return GameState.run.get_player(peer_id)


# --- solo ------------------------------------------------------------------


func test_solo_yes_extracts_immediately() -> void:
	_start_run([1])
	GameState.request_extract_vote(1, true)
	assert_eq(_ended_results.size(), 1, "a solo yes ends the run")
	assert_eq(_ended_results[0].reason, RunEndReason.Reason.EXTRACT)
	assert_null(GameState.run)


func test_solo_no_leaves_the_run_going() -> void:
	_start_run([1])
	GameState.request_extract_vote(1, false)
	assert_true(_ended_results.is_empty(), "a no never extracts")
	assert_not_null(GameState.run)


# --- co-op -----------------------------------------------------------------


func test_co_op_waits_for_every_living_player() -> void:
	_start_run([1, 2])
	GameState.request_extract_vote(1, true)
	assert_true(_ended_results.is_empty(), "one yes of two is not enough")
	assert_eq(GameState.run.vote_state().size(), 1)
	GameState.request_extract_vote(2, true)
	assert_eq(_ended_results.size(), 1, "the second yes extracts")
	assert_eq(_ended_results[0].reason, RunEndReason.Reason.EXTRACT)


func test_co_op_three_players_need_three_yes() -> void:
	_start_run([1, 2, 3])
	GameState.request_extract_vote(1, true)
	GameState.request_extract_vote(2, true)
	assert_true(_ended_results.is_empty(), "two of three is not unanimous")
	GameState.request_extract_vote(3, true)
	assert_eq(_ended_results.size(), 1)


func test_a_no_cancels_and_empties_the_tally() -> void:
	_start_run([1, 2])
	GameState.request_extract_vote(1, true)
	GameState.request_extract_vote(2, false)
	assert_true(_ended_results.is_empty(), "a no cancels the call")
	assert_false(GameState.run.has_open_vote(), "the tally is empty")
	assert_not_null(GameState.run, "the rope stays usable")


func test_a_fresh_call_after_a_cancel_starts_from_zero() -> void:
	_start_run([1, 2])
	GameState.request_extract_vote(1, true)
	GameState.request_extract_vote(2, false)
	GameState.request_extract_vote(2, true)
	assert_true(_ended_results.is_empty(), "peer 1's old yes does not carry over")
	assert_eq(GameState.run.vote_state().size(), 1)
	GameState.request_extract_vote(1, true)
	assert_eq(_ended_results.size(), 1, "both yes on the new call extract")


func test_a_repeated_yes_does_not_count_twice() -> void:
	_start_run([1, 2])
	GameState.request_extract_vote(1, true)
	GameState.request_extract_vote(1, true)
	assert_true(_ended_results.is_empty(), "one peer cannot vote for two")
	assert_eq(GameState.run.vote_state().size(), 1)


# --- downed and dead players ----------------------------------------------


func test_downed_player_is_excluded_from_the_tally() -> void:
	_start_run([1, 2])
	_slice(2).is_downed = true
	GameState.request_extract_vote(1, true)
	assert_eq(_ended_results.size(), 1, "the living player's yes extracts alone")


func test_dead_player_is_excluded_from_the_tally() -> void:
	_start_run([1, 2, 3])
	_slice(3).is_dead = true
	GameState.request_extract_vote(1, true)
	assert_true(_ended_results.is_empty())
	GameState.request_extract_vote(2, true)
	assert_eq(_ended_results.size(), 1, "two living yes votes are unanimous")


func test_a_downed_players_vote_is_ignored() -> void:
	_start_run([1, 2])
	_slice(2).is_downed = true
	GameState.request_extract_vote(2, true)
	assert_false(GameState.run.has_open_vote(), "a downed yes is not recorded")
	assert_true(_ended_results.is_empty())


func test_a_downed_players_no_cannot_cancel() -> void:
	_start_run([1, 2, 3])
	GameState.request_extract_vote(1, true)
	_slice(3).is_downed = true
	GameState.request_extract_vote(3, false)
	assert_eq(GameState.run.vote_state().size(), 1, "the open call survives a downed no")


func test_all_downed_never_extracts_by_vote() -> void:
	_start_run([1, 2])
	_slice(1).is_downed = true
	_slice(2).is_downed = true
	GameState.request_extract_vote(1, true)
	GameState.request_extract_vote(2, true)
	assert_true(_ended_results.is_empty(), "no living player means no vote can pass")


# --- guards and broadcast --------------------------------------------------


func test_a_client_refuses_the_vote() -> void:
	_start_run([1, 2])
	NetworkManager.is_host = false
	GameState.request_extract_vote(1, true)
	assert_false(GameState.run.has_open_vote(), "only the host tallies")
	NetworkManager.is_host = true


func test_a_vote_from_outside_the_run_is_refused() -> void:
	_start_run([1, 2])
	GameState.request_extract_vote(9, true)
	assert_false(GameState.run.has_open_vote())


func test_no_vote_without_a_live_run() -> void:
	NetworkManager.start_solo()
	GameState.request_extract_vote(1, true)
	assert_true(_ended_results.is_empty())


func test_every_change_is_broadcast() -> void:
	_start_run([1, 2])
	GameState.request_extract_vote(1, true)
	assert_eq(_vote_broadcasts.size(), 1)
	assert_true(_vote_broadcasts[0].has(1))
	GameState.request_extract_vote(2, false)
	assert_eq(_vote_broadcasts.size(), 2, "the cancel is broadcast")
	assert_true(_vote_broadcasts[1].is_empty(), "with an empty tally")


func test_a_downed_voters_yes_does_not_count_for_the_living() -> void:
	_start_run([1, 2, 3])
	GameState.request_extract_vote(2, true)
	_slice(2).is_downed = true
	GameState.request_extract_vote(1, true)
	assert_eq(_ended_results.size(), 0, "peer 3 has not agreed")
	GameState.request_extract_vote(3, true)
	assert_eq(_ended_results.size(), 1)
	assert_eq(_ended_results[0].reason, RunEndReason.Reason.EXTRACT)


func test_the_vote_resolves_when_the_last_holdout_goes_down() -> void:
	_start_run([1, 2, 3])
	GameState.request_extract_vote(1, true)
	GameState.request_extract_vote(2, true)
	assert_eq(_ended_results.size(), 0)
	var holdout: Player = Player.new()
	holdout.peer_id = 3
	GameState._on_player_downed(holdout)
	holdout.free()
	assert_eq(_ended_results.size(), 1, "both living players had already agreed")
	assert_eq(_ended_results[0].reason, RunEndReason.Reason.EXTRACT)
