extends GutTest
## Tests for the Shrine interactable and the SHRINE room populator
## (SPEC-relics "Shrine flow", W4-B5): the host rolls three relics the acting
## player does not already hold at `max_stacks`, announces them through
## `relic_choice_offered(peer_id, ids)`, refuses a second use by the *same* peer
## while a *different* peer may still use the shrine, and the populator
## registration is a guarded no-op until Dev A's FloorGenerator registry lands.
## Owned by relics.
##
## after_each clears GameState.run / forced_seed and the NetworkManager session
## so no autoload state leaks into the next test file (LESSONS). Signals are
## captured with named method callbacks, never lambdas (LESSONS).

const SHRINE_SCENE_PATH: String = "res://scenes/dungeon/interactables/shrine.tscn"
const SHRINE_SCRIPT_PATH: String = "res://scripts/relics/shrine.gd"
const REGISTRY_STUB_PATH: String = "res://tests/helpers/shrine_registry_stub.gd"
const HOST_PEER: int = 1
const GUEST_PEER: int = 2

## Every offer announced on the shrine, as {peer_id, ids}.
var _offers: Array[Dictionary] = []
## Peer ids from Shrine.interaction_forwarded (client -> request_* path).
var _forwarded: Array[int] = []
## Every refusal, as {peer_id, reason}.
var _refusals: Array[Dictionary] = []
var _shrine: Shrine = null


func before_each() -> void:
	GameState.run = null
	GameState.forced_seed = 0
	_offers.clear()
	_forwarded.clear()
	_refusals.clear()
	NetworkManager.start_solo()
	_shrine = _make_shrine(_shrine_scene())


func after_each() -> void:
	_shrine = null
	GameState.run = null
	GameState.forced_seed = 0
	GameState.last_advance_refusal = GameState.ADVANCE_REFUSAL_NONE
	NetworkManager.disconnect_all()


func _on_offered(peer_id: int, ids: Array[StringName]) -> void:
	_offers.append({"peer_id": peer_id, "ids": ids})


func _on_forwarded(peer_id: int) -> void:
	_forwarded.append(peer_id)


func _on_refused(peer_id: int, reason: StringName) -> void:
	_refusals.append({"peer_id": peer_id, "reason": reason})


func _shrine_scene() -> PackedScene:
	var packed: PackedScene = load(SHRINE_SCENE_PATH) as PackedScene
	assert_not_null(packed, "%s loads" % SHRINE_SCENE_PATH)
	return packed


## Builds a shrine from the real scene, wired to this test's recorders.
func _make_shrine(packed: PackedScene) -> Shrine:
	var shrine: Shrine = packed.instantiate() as Shrine
	assert_not_null(shrine, "the shrine scene's root is a Shrine")
	add_child_autofree(shrine)
	if shrine == null:
		return null
	shrine.relic_choice_offered.connect(_on_offered)
	shrine.interaction_forwarded.connect(_on_forwarded)
	shrine.use_refused.connect(_on_refused)
	return shrine


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


## A player double: a bare Player node is enough, because the shrine reads only
## `peer_id` off the interactor (the spec's interaction is the player's, the
## host decides the offer). Deliberately never added to the tree: the real
## scene's children belong to player-controller.
func _player(peer_id: int) -> Player:
	var player: Player = Player.new()
	player.peer_id = peer_id
	autofree(player)
	return player


## Records `ids` in the acting peer's run slice, `copies` times each, so the
## roller sees the player already holding them.
func _hold(player: Player, ids: Array[StringName], copies: int) -> void:
	var slice: RunPlayerState = RelicRoller.run_slice(player)
	assert_not_null(slice, "the run keeps a slice for peer %d" % player.peer_id)
	if slice == null:
		return
	for id: StringName in ids:
		for _copy: int in range(copies):
			slice.relics.append(id)


## Holds every relic in `pool` at its own `max_stacks` except the ones in
## `spared`, and returns the ids that therefore stay offerable.
func _hold_all_but(player: Player, pool: Array[RelicData], spared: Array[StringName]) -> Array[StringName]:
	var offerable: Array[StringName] = []
	var slice: RunPlayerState = RelicRoller.run_slice(player)
	assert_not_null(slice, "the run keeps a slice for the acting peer")
	if slice == null:
		return offerable
	for data: RelicData in pool:
		if data == null:
			continue
		if spared.has(data.id):
			offerable.append(data.id)
			continue
		for _copy: int in range(maxi(data.max_stacks, 1)):
			slice.relics.append(data.id)
	return offerable


func _sorted(ids: Array[StringName]) -> Array[StringName]:
	var out: Array[StringName] = ids.duplicate()
	out.sort()
	return out


func _distinct(ids: Array[StringName]) -> Array[StringName]:
	var out: Array[StringName] = []
	for id: StringName in ids:
		if not out.has(id):
			out.append(id)
	return out


func _read(path: String) -> String:
	return FileAccess.get_file_as_string(path)


func _has_property(node: Object, property_name: String) -> bool:
	for entry: Dictionary in node.get_property_list():
		if String(entry.get("name", "")) == property_name:
			return true
	return false


# --- the shrine as an interactable ----------------------------------------


func test_the_shrine_scene_lives_where_spec_project_puts_interactables() -> void:
	assert_true(FileAccess.file_exists(SHRINE_SCENE_PATH),
		"%s exists (SPEC-project: scenes/dungeon/interactables/)" % SHRINE_SCENE_PATH)
	assert_true(FileAccess.file_exists(SHRINE_SCRIPT_PATH), "%s exists" % SHRINE_SCRIPT_PATH)


func test_the_shrine_scene_instantiates_as_a_shrine() -> void:
	assert_not_null(_shrine)
	if _shrine == null:
		return
	assert_true(_shrine.prompt_text.length() > 0, "the shrine offers an interact prompt")
	assert_eq(_shrine.hold_seconds, 0.0, "the shrine is a press, not a hold (revive is the only hold)")
	assert_eq(_shrine.collision_layer, Shrine.INTERACTABLE_LAYER,
		"the shrine sits on the interactable physics layer")
	assert_eq(_shrine.get_child_count(), 2, "the scene carries an interact shape and placeholder art")


func test_the_shrine_satisfies_the_interactable_contract_the_player_scans_for() -> void:
	var stub: InteractableStub = InteractableStub.new()
	add_child_autofree(stub)
	for name: String in ["prompt_text", "hold_seconds"]:
		assert_true(_has_property(_shrine, name), "Shrine exposes %s like Interactable does" % name)
		assert_true(_has_property(stub, name), "the stub exposes %s" % name)
	assert_true(_shrine.has_method("interact"), "the player's scan duck-types on interact()")
	assert_true(stub.has_method("interact"))
	stub.interact(null)
	assert_eq(stub.interactions, 1, "the stub records the call it stands in for")


func test_the_shrine_records_its_sync_contract_and_the_dev_a_blocker() -> void:
	var source: String = _read(SHRINE_SCRIPT_PATH)
	assert_true(source.contains("Sync:"), "every stateful script states who owns it and how it syncs")
	assert_true(source.contains("blocked on Dev A (W4-A3)"),
		"the SHRINE room placement is Dev A's; the blocker is recorded in the code")


func test_the_offer_size_is_the_specs_three() -> void:
	assert_eq(Shrine.OFFER_COUNT, 3, "SPEC-relics: the shrine rolls 3 relics")
	assert_false(Shrine.ALLOW_CURSED, "SPEC-relics: cursed never roll at shrines")


# --- the host's roll ------------------------------------------------------


func test_a_host_interaction_offers_three_relics_the_player_does_not_hold() -> void:
	_start_run([HOST_PEER])
	var player: Player = _player(HOST_PEER)
	var pool_ids: Array[StringName] = RelicRoller.ids_of(RelicRoller.load_pool())
	assert_gt(pool_ids.size(), Shrine.OFFER_COUNT, "the shipped relic folder holds more than an offer")
	_shrine.interact(player)
	assert_eq(_offers.size(), 1, "one use, one offer")
	if _offers.is_empty():
		return
	var ids: Array[StringName] = _offers[0]["ids"]
	assert_eq(int(_offers[0]["peer_id"]), HOST_PEER, "the offer is announced for the acting peer")
	assert_eq(ids.size(), Shrine.OFFER_COUNT, "three ids come back from a pool that can spare them")
	assert_eq(_sorted(ids), _sorted(_distinct(ids)), "the three are distinct")
	for id: StringName in ids:
		assert_true(pool_ids.has(id), "%s comes from the relic content folder" % id)
	assert_eq(_shrine.offer_of(HOST_PEER), ids, "the offer is recorded for the peer that received it")


func test_the_offer_never_holds_a_relic_the_player_has_at_max_stacks() -> void:
	_start_run([HOST_PEER])
	var player: Player = _player(HOST_PEER)
	var pool: Array[RelicData] = RelicRoller.load_pool()
	assert_gt(pool.size(), 2, "the shipped relic folder holds more than two relics")
	var spared: Array[StringName] = [pool[0].id, pool[1].id]
	var offerable: Array[StringName] = _hold_all_but(player, pool, spared)
	assert_eq(offerable.size(), 2, "exactly two relics are still below max_stacks")
	_shrine.interact(player)
	assert_eq(_offers.size(), 1, "the shrine offered once")
	if _offers.is_empty():
		return
	var ids: Array[StringName] = _offers[0]["ids"]
	assert_eq(_sorted(ids), _sorted(offerable),
		"the offer is exactly the relics the player does not already hold at max_stacks")
	assert_lt(ids.size(), Shrine.OFFER_COUNT,
		"an exhausted pool offers fewer than three rather than repeating a held relic")


func test_the_rolled_offer_is_seeded_from_the_run_not_the_clock() -> void:
	_start_run([HOST_PEER])
	_shrine.interact(_player(HOST_PEER))
	var first: Array[StringName] = _offers[0]["ids"]
	var second_shrine: Shrine = _make_shrine(_shrine_scene())
	second_shrine.interact(_player(HOST_PEER))
	assert_eq(_offers.size(), 2, "the second shrine offers too")
	if _offers.size() < 2:
		return
	assert_eq(_sorted(_offers[1]["ids"]), _sorted(first),
		"the same run seed rolls the same offer (RelicRoller.seeded_rng)")


func test_interacting_without_a_live_run_is_refused() -> void:
	_become_host()
	assert_null(GameState.run)
	_shrine.interact(_player(HOST_PEER))
	assert_true(_offers.is_empty(), "no run, nothing to offer")
	assert_eq(_refusals.size(), 1, "the use is refused, not silently dropped")
	if _refusals.is_empty():
		return
	assert_eq(int(_refusals[0]["peer_id"]), HOST_PEER)
	assert_eq(String(_refusals[0]["reason"]), String(Shrine.REFUSAL_NO_RUN))
	assert_false(_shrine.has_used(HOST_PEER), "a refused use does not spend the shrine")


# --- one use per peer per shrine ------------------------------------------


func test_a_second_use_by_the_same_peer_is_refused_while_another_peer_may_still_use_it() -> void:
	_start_run([HOST_PEER, GUEST_PEER])
	_shrine.interact(_player(HOST_PEER))
	assert_eq(_offers.size(), 1, "the first use offers")
	assert_true(_shrine.has_used(HOST_PEER), "the host records one use per peer per shrine")
	assert_false(_shrine.is_usable(HOST_PEER), "the same peer may not use it twice")
	_shrine.interact(_player(HOST_PEER))
	assert_eq(_offers.size(), 1, "the second use announces nothing")
	assert_eq(_refusals.size(), 1, "the second use is refused")
	if _refusals.is_empty():
		return
	assert_eq(int(_refusals[0]["peer_id"]), HOST_PEER)
	assert_eq(String(_refusals[0]["reason"]), String(Shrine.REFUSAL_ALREADY_USED))
	assert_true(_shrine.is_usable(GUEST_PEER), "another peer has not used the shrine")
	_shrine.interact(_player(GUEST_PEER))
	assert_eq(_offers.size(), 2, "a different peer still gets its own offer")
	if _offers.size() < 2:
		return
	assert_eq(int(_offers[1]["peer_id"]), GUEST_PEER, "the second offer is the other peer's")


func test_interacting_with_no_player_uses_the_local_peer() -> void:
	_start_run([HOST_PEER])
	_shrine.interact(null)
	assert_eq(_offers.size(), 1, "an unnamed interactor is still an interaction")
	if _offers.is_empty():
		return
	assert_eq(int(_offers[0]["peer_id"]), NetworkManager.local_peer_id,
		"an unnamed interactor is the local peer")


# --- a client never rolls -------------------------------------------------


func test_a_client_interaction_forwards_and_never_rolls_locally() -> void:
	_start_run([HOST_PEER, GUEST_PEER])
	NetworkManager.is_host = false
	_shrine.interact(_player(GUEST_PEER))
	assert_eq(_forwarded, [GUEST_PEER] as Array[int], "the client hands its use to the request path")
	assert_true(_offers.is_empty(), "a client never rolls")
	assert_true(_refusals.is_empty(), "a client refuses nothing: the host validates")
	assert_false(_shrine.has_used(GUEST_PEER), "a client records nothing locally")
	assert_false(NetworkManager.can_send_request(),
		"a solo/offline session has no remote host, so nothing is sent")


func test_a_client_interaction_without_a_session_is_refused() -> void:
	_start_run([HOST_PEER, GUEST_PEER])
	NetworkManager.disconnect_all()
	_shrine.interact(_player(GUEST_PEER))
	assert_true(_forwarded.is_empty(), "an inactive session forwards nothing")
	assert_true(_offers.is_empty(), "and offers nothing")


# --- the SHRINE populator and its registration seam -----------------------


func test_the_shrine_populator_callable_targets_the_shrine_populator() -> void:
	var populator: Callable = Shrine.shrine_populator()
	assert_true(populator.is_valid(), "the registry gets a valid Callable")
	assert_eq(populator.get_method(), &"_populate_shrine_room",
		"the Callable the registry holds is the SHRINE populator")


func test_the_populator_is_registered_under_the_shrine_room_type() -> void:
	var stub: Script = load(REGISTRY_STUB_PATH) as Script
	assert_not_null(stub, "%s loads" % REGISTRY_STUB_PATH)
	if stub == null:
		return
	var constants: Dictionary = stub.get_script_constant_map()
	var room_types: Dictionary = constants.get(&"RoomType", {})
	assert_true(room_types.has("SHRINE") and room_types.has("ROPE"), "the stub declares both room types")
	assert_ne(room_types.get("SHRINE"), room_types.get("ROPE"),
		"the two keys differ, so looking up the wrong one is visible")
	assert_eq(Shrine.room_type_value(stub), room_types.get("SHRINE"),
		"the registration resolves RoomType.SHRINE, not another type")
	assert_null(Shrine.room_type_value(Shrine), "a script with no RoomType enumeration resolves nothing")


func test_registering_the_populator_is_guarded_and_a_second_call_is_inert() -> void:
	var registry_exists: bool = ResourceLoader.exists(Shrine.GENERATOR_SCRIPT_PATH)
	assert_eq(Shrine.register_populator(), registry_exists,
		"registration succeeds exactly when Dev A's FloorGenerator script exists")
	assert_eq(Shrine.register_populator(), registry_exists, "the second call returns the same verdict")
	assert_eq(Shrine.blocker_warnings(), 0 if registry_exists else 1,
		"the blocked path notes its blocker exactly once per process, not once per call")
	if not registry_exists:
		assert_eq(Shrine.register_populator(), false, "and it stays a no-op")
		assert_eq(Shrine.blocker_warnings(), 1, "with no further warning")
	assert_true(Shrine.shrine_populator().is_valid(),
		"the populator is buildable whether or not the registry is there")


func test_the_populator_spawns_one_shrine_in_a_room_on_the_host() -> void:
	_become_host()
	var room: Node = Node2D.new()
	add_child_autofree(room)
	Shrine.shrine_populator().call(room)
	assert_eq(_count_shrines(room), 1, "a SHRINE room gets exactly one shrine")
	var spawned: Shrine = room.get_child(0) as Shrine
	assert_not_null(spawned, "the child is a Shrine")
	assert_eq(spawned.position, Vector2.ZERO, "the shrine sits at the room's origin until the anchor lands")


func test_the_populator_adds_a_second_shrine_per_call_and_nothing_on_a_client() -> void:
	_become_host()
	var room: Node = Node2D.new()
	add_child_autofree(room)
	Shrine.shrine_populator().call(room)
	Shrine.shrine_populator().call(room)
	assert_eq(_count_shrines(room), 2, "the populator spawns per call")
	NetworkManager.is_host = false
	Shrine.shrine_populator().call(room)
	assert_eq(_count_shrines(room), 2, "populators run on the host only")


func test_the_populator_tolerates_a_missing_room() -> void:
	_become_host()
	Shrine.shrine_populator().call(null)
	pass_test("a null room is refused rather than crashing")


func _count_shrines(node: Node) -> int:
	var count: int = 0
	for child: Node in node.get_children():
		if child is Shrine:
			count += 1
	return count
