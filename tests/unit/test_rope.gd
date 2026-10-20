extends GutTest
## Tests for the extraction rope and the ROPE room populator
## (SPEC-run-economy, W3-B2a): a solo host interacting with the rope ends the
## run immediately with EXTRACT, co-op prints the week-5 vote deferral and
## leaves the rope usable, a client routes the interaction through the
## request_* RPC and never ends its own run, and the populator registration is
## a guarded no-op until Dev A's FloorGenerator registry lands.
## Owned by run-economy.
##
## after_each clears GameState.run / forced_seed and the NetworkManager session
## so no autoload state leaks into the next test file (LESSONS). Signals are
## captured with named method callbacks, never lambdas (LESSONS).

const ROPE_SCENE_PATH: String = "res://scenes/dungeon/interactables/rope.tscn"
const ROPE_SCRIPT_PATH: String = "res://scripts/run/rope.gd"
const HOST_PEER: int = 1

## Run results from GameState.run_ended, one per end_run that actually ended a run.
var _ended: Array[RunResult] = []
## Peer ids from Rope.interaction_forwarded (client -> request_* path).
var _forwarded: Array[int] = []
## Peer ids from Rope.extract_applied (the host ended the run).
var _applied: Array[int] = []
## Peer ids from Rope.extract_deferred (co-op, the week-5 vote prompt).
var _deferred: Array[int] = []
var _rope: Rope = null


func before_each() -> void:
	GameState.run = null
	GameState.forced_seed = 0
	_ended.clear()
	_forwarded.clear()
	_applied.clear()
	_deferred.clear()
	NetworkManager.start_solo()
	GameState.run_ended.connect(_record_ended)
	_rope = _make_rope(_rope_scene())


func after_each() -> void:
	if GameState.run_ended.is_connected(_record_ended):
		GameState.run_ended.disconnect(_record_ended)
	_rope = null
	GameState.run = null
	GameState.forced_seed = 0
	GameState.last_advance_refusal = GameState.ADVANCE_REFUSAL_NONE
	NetworkManager.disconnect_all()


func _record_ended(result: RefCounted) -> void:
	var typed: RunResult = result as RunResult
	if typed != null:
		_ended.append(typed)


func _on_forwarded(peer_id: int) -> void:
	_forwarded.append(peer_id)


func _on_applied(peer_id: int) -> void:
	_applied.append(peer_id)


func _on_deferred(peer_id: int) -> void:
	_deferred.append(peer_id)


func _rope_scene() -> PackedScene:
	var packed: PackedScene = load(ROPE_SCENE_PATH) as PackedScene
	assert_not_null(packed, "%s loads" % ROPE_SCENE_PATH)
	return packed


## Builds a rope from the real scene, wired to this test's recorders.
func _make_rope(packed: PackedScene) -> Rope:
	var rope: Rope = packed.instantiate() as Rope
	assert_not_null(rope, "the rope scene's root is a Rope")
	add_child_autofree(rope)
	if rope == null:
		return null
	rope.interaction_forwarded.connect(_on_forwarded)
	rope.extract_applied.connect(_on_applied)
	rope.extract_deferred.connect(_on_deferred)
	return rope


## A solo session is a host with one peer — the same code path co-op uses.
func _become_host() -> void:
	NetworkManager.start_solo()
	assert_true(NetworkManager.is_host, "test session is a host")


func _party(peer_ids: Array[int]) -> Array[PlayerSpawnInfo]:
	var party: Array[PlayerSpawnInfo] = []
	for peer_id: int in peer_ids:
		party.append(PlayerSpawnInfo.new(peer_id))
	return party


func _start_run(peer_ids: Array[int]) -> void:
	_become_host()
	GameState.forced_seed = 777
	GameState.start_run(0, 2, _party(peer_ids))
	assert_not_null(GameState.run, "the run is live")


## A player double: a bare Player node is enough, because the rope only reads
## `peer_id` off the interactor (SPEC-run-economy: the interaction is the
## player's, the host decides the extraction). It is deliberately never added to
## the tree: the real scene's children belong to player-controller, and this test
## only needs the peer id.
func _player(peer_id: int) -> Player:
	var player: Player = Player.new()
	player.peer_id = peer_id
	autofree(player)
	return player


func _read(path: String) -> String:
	return FileAccess.get_file_as_string(path)


# --- the rope as an interactable ------------------------------------------


func test_the_rope_scene_lives_where_spec_project_puts_interactables() -> void:
	assert_true(FileAccess.file_exists(ROPE_SCENE_PATH),
		"%s exists (SPEC-project: scenes/dungeon/interactables/)" % ROPE_SCENE_PATH)
	assert_true(FileAccess.file_exists(ROPE_SCRIPT_PATH), "%s exists" % ROPE_SCRIPT_PATH)


func test_the_rope_scene_instantiates_as_a_rope() -> void:
	assert_not_null(_rope)
	if _rope == null:
		return
	assert_true(_rope.prompt_text.length() > 0, "the rope offers an interact prompt")
	assert_eq(_rope.hold_seconds, 0.0, "the rope is a press, not a hold (revive is the only hold)")
	assert_eq(_rope.collision_layer, Rope.INTERACTABLE_LAYER,
		"the rope sits on the interactable physics layer")
	assert_eq(_rope.get_child_count(), 2, "the scene carries an interact shape and placeholder art")


func test_the_rope_satisfies_the_interactable_contract_the_player_scans_for() -> void:
	var stub: InteractableStub = InteractableStub.new()
	add_child_autofree(stub)
	for name: String in ["prompt_text", "hold_seconds"]:
		assert_true(_has_property(_rope, name), "Rope exposes %s like Interactable does" % name)
		assert_true(_has_property(stub, name), "the stub exposes %s" % name)
	assert_true(_rope.has_method("interact"), "the player's scan duck-types on interact()")
	assert_true(stub.has_method("interact"))
	stub.interact(null)
	assert_eq(stub.interactions, 1, "the stub records the call it stands in for")


func _has_property(node: Object, property_name: String) -> bool:
	for entry: Dictionary in node.get_property_list():
		if String(entry.get("name", "")) == property_name:
			return true
	return false


func test_the_rope_records_its_sync_contract_and_the_dev_a_blocker() -> void:
	var source: String = _read(ROPE_SCRIPT_PATH)
	assert_true(source.contains("Sync:"), "every stateful script states who owns it and how it syncs")
	assert_true(source.contains("blocked on Dev A (W3-A3)"),
		"the ROPE populator registry is Dev A's; the blocker is recorded in the code")


# --- solo: immediate extraction -------------------------------------------


func test_a_solo_host_interaction_ends_the_run_with_extract() -> void:
	_start_run([HOST_PEER])
	_rope.interact(_player(HOST_PEER))
	assert_eq(_ended.size(), 1, "the run ended exactly once")
	assert_eq(_ended[0].reason, RunEndReason.Reason.EXTRACT, "a rope extraction, not a defeat")
	assert_null(GameState.run, "the run is over")
	assert_eq(_applied, [HOST_PEER] as Array[int], "the use was applied on the host")
	assert_eq(_deferred, [] as Array[int], "a solo rope never defers to a vote")
	assert_eq(_forwarded, [] as Array[int], "the host never forwards its own use")


func test_a_solo_interaction_twice_ends_the_run_once() -> void:
	_start_run([HOST_PEER])
	_rope.interact(_player(HOST_PEER))
	_rope.interact(_player(HOST_PEER))
	assert_eq(_ended.size(), 1, "the second use has no run left to extract from")
	assert_false(_rope.is_usable(), "a rope with no live run cannot be used")


func test_the_rope_reports_the_deferral_once_per_use_and_stays_usable() -> void:
	_start_run([HOST_PEER, 2])
	_rope.interact(_player(HOST_PEER))
	assert_true(_rope.is_usable(), "co-op leaves the rope usable")
	_rope.interact(_player(HOST_PEER))
	assert_eq(_deferred.size(), 2, "every co-op use reports the deferral")


func test_interacting_without_a_live_run_does_nothing() -> void:
	_become_host()
	assert_null(GameState.run)
	_rope.interact(_player(HOST_PEER))
	assert_true(_ended.is_empty(), "no run, nothing to extract")
	assert_true(_applied.is_empty())
	assert_true(_deferred.is_empty())
	assert_false(_rope.is_usable())


func test_interacting_with_no_player_uses_the_local_peer() -> void:
	_start_run([HOST_PEER])
	_rope.interact(null)
	assert_eq(_applied, [NetworkManager.local_peer_id] as Array[int],
		"an unnamed interactor is the local peer")


# --- co-op: the week-5 vote prompt is deferred -----------------------------


func test_a_co_op_interaction_defers_to_the_week_5_vote_and_leaves_the_run_live() -> void:
	_start_run([HOST_PEER, 2])
	_rope.interact(_player(HOST_PEER))
	assert_true(_ended.is_empty(), "the vote prompt lands in week 5, so no extract yet")
	assert_not_null(GameState.run, "the run carries on")
	assert_true(_rope.is_usable(), "the rope stays usable until the vote passes")
	assert_eq(_deferred, [HOST_PEER] as Array[int], "the deferral is recorded with the acting peer")
	assert_eq(_applied, [] as Array[int], "nothing was applied")


func test_a_co_op_interaction_uses_the_run_party_not_the_peer_registry() -> void:
	# Two players in the run but only the host in the peer registry: the party
	# in RunState is the roster the vote is measured against.
	_start_run([HOST_PEER, 2])
	NetworkManager.peer_ids = [HOST_PEER] as Array[int]
	_rope.interact(_player(HOST_PEER))
	assert_true(_ended.is_empty(), "co-op defers even when the registry is thin")
	assert_eq(_deferred, [HOST_PEER] as Array[int])


# --- a client never ends its own run --------------------------------------


func test_a_client_interaction_routes_through_request_and_never_ends_the_run() -> void:
	_start_run([HOST_PEER, 2])
	NetworkManager.is_host = false
	_rope.interact(_player(2))
	assert_eq(_forwarded, [2] as Array[int], "the client hands its use to the request path")
	assert_true(_ended.is_empty(), "a client never ends the run")
	assert_not_null(GameState.run, "the client's run survives its own interaction")
	assert_true(_applied.is_empty(), "the client applies nothing locally")
	assert_eq(NetworkManager.HOST_PEER_ID, 1, "the request goes to the host peer")
	assert_false(NetworkManager.can_send_request(),
		"a solo/offline session has no remote host, so nothing is sent")


func test_can_send_request_needs_a_joined_client_on_a_real_session() -> void:
	_become_host()
	assert_false(NetworkManager.can_send_request(), "a solo host sends no requests")
	NetworkManager.is_host = false
	assert_false(NetworkManager.can_send_request(),
		"an offline peer reports is_server(), so there is no remote host to ask")
	NetworkManager.disconnect_all()
	assert_false(NetworkManager.can_send_request(), "an inactive session sends nothing")


func test_a_client_interaction_without_a_session_is_refused() -> void:
	_start_run([HOST_PEER, 2])
	NetworkManager.disconnect_all()
	_rope.interact(_player(2))
	assert_true(_ended.is_empty(), "with no session there is nobody to ask")
	assert_eq(_forwarded, [] as Array[int], "an inactive session forwards nothing")


# --- the request_* RPC a client's rope use travels on ----------------------


func test_the_rope_request_is_a_sender_validated_host_rpc() -> void:
	assert_true(NetworkManager.has_method("request_vote_rope"),
		"a client's rope use travels on request_vote_rope (SPEC-networking, SPEC-run-economy)")
	_become_host()
	assert_true(NetworkManager.can_apply_rope_request(2),
		"a remote client's use is applied by the host")
	assert_false(NetworkManager.can_apply_rope_request(0),
		"a direct local call is not a client request")
	NetworkManager.is_host = false
	assert_false(NetworkManager.can_apply_rope_request(2), "clients apply nothing")


func test_a_locally_invoked_rope_request_never_ends_the_run() -> void:
	_start_run([HOST_PEER, 2])
	NetworkManager.request_vote_rope(true)
	assert_true(_ended.is_empty(), "the vote tally is week 5; nothing extracts yet")
	assert_not_null(GameState.run, "the run carries on")


func test_a_client_cannot_apply_its_own_rope_request() -> void:
	_start_run([HOST_PEER, 2])
	NetworkManager.is_host = false
	NetworkManager.request_vote_rope(true)
	assert_true(_ended.is_empty(), "requests are applied on the host only")
	assert_not_null(GameState.run)


# --- the ROPE populator and its registration seam --------------------------


func test_the_rope_populator_callable_targets_the_rope_populator() -> void:
	var populator: Callable = Rope.rope_populator()
	assert_true(populator.is_valid(), "the registry gets a valid Callable")
	assert_eq(populator.get_method(), &"_populate_rope_room",
		"the Callable the registry holds is the ROPE populator")


func test_registering_the_populator_is_guarded_until_dev_as_registry_lands() -> void:
	var registry_exists: bool = ResourceLoader.exists(Rope.GENERATOR_SCRIPT_PATH)
	assert_eq(Rope.register_populator(), registry_exists,
		"registration succeeds exactly when Dev A's FloorGenerator script exists")
	assert_true(Rope.rope_populator().is_valid(),
		"the populator is buildable whether or not the registry is there")


func test_the_populator_spawns_one_rope_in_a_room_on_the_host() -> void:
	_become_host()
	var room: Node = Node2D.new()
	add_child_autofree(room)
	Rope.rope_populator().call(room)
	assert_eq(_count_ropes(room), 1, "a ROPE room gets exactly one rope")
	var spawned: Rope = room.get_child(0) as Rope
	assert_not_null(spawned, "the child is a Rope")
	assert_eq(spawned.position, Vector2.ZERO, "the rope sits at the room's origin until the anchor lands")


func test_the_populator_adds_a_second_rope_per_call_and_nothing_on_a_client() -> void:
	_become_host()
	var room: Node = Node2D.new()
	add_child_autofree(room)
	Rope.rope_populator().call(room)
	Rope.rope_populator().call(room)
	assert_eq(_count_ropes(room), 2, "the populator spawns per call")
	NetworkManager.is_host = false
	Rope.rope_populator().call(room)
	assert_eq(_count_ropes(room), 2, "populators run on the host only")


func test_the_populator_tolerates_a_missing_room() -> void:
	_become_host()
	Rope.rope_populator().call(null)
	pass_test("a null room is refused rather than crashing")


func _count_ropes(node: Node) -> int:
	var count: int = 0
	for child: Node in node.get_children():
		if child is Rope:
			count += 1
	return count
