extends GutTest
## Tests for floor sync (SPEC-networking "Seed sync", W3-B3a and W3-B3b): the
## host's `floor_ready(seed, floor_index, biome_id, modifiers)` broadcast, the
## client generating the same floor locally through the lane-B generator seam,
## the sender validation that stops a client declaring a floor, the `--seed`
## plumbing from the launch arg through `GameState.start_run` into the seed that
## is broadcast, and the layout-hash assertion with its host-layout fallback (a
## mismatch logs an error, records the divergence and asks the host for its own
## layout instead of regenerating). Owned by networking.
##
## after_each clears GameState.run / forced_seed / the remote-floor and
## divergence fields, the NetworkManager session and the seam's injected
## generator, so no autoload or static state leaks into the next test file
## (LESSONS). Signals are captured with named method callbacks, never lambdas
## (LESSONS).
##
## A single-process suite cannot fake a client — an unstarted ENet peer reports
## `is_server() == true` (LESSONS) — so the client's receive path is driven by
## setting `NetworkManager.is_host` false and calling the apply path; the real
## two-process client is the W3-B3a-2 smoke.

const HOST_PEER: int = 1
const CLIENT_PEER: int = 2
const FORCED_SEED: int = 20261020

## Floors GameState.floor_changed named, as {floor_index, biome_id}.
var _floors: Array[Dictionary] = []
## Floors this peer asked the host's layout for, in order.
var _layout_requests: Array[int] = []


func before_each() -> void:
	_reset_autoloads()
	_floors.clear()
	_layout_requests.clear()
	GameState.floor_changed.connect(_on_floor_changed)
	NetworkManager.floor_layout_requested.connect(_on_layout_requested)


func after_each() -> void:
	if GameState.floor_changed.is_connected(_on_floor_changed):
		GameState.floor_changed.disconnect(_on_floor_changed)
	if NetworkManager.floor_layout_requested.is_connected(_on_layout_requested):
		NetworkManager.floor_layout_requested.disconnect(_on_layout_requested)
	FloorGeneratorSeam.clear_injected_generator()
	_reset_autoloads()


func _reset_autoloads() -> void:
	GameState.run = null
	GameState.forced_seed = 0
	GameState.remote_floor_index = 0
	GameState.remote_floor_modifiers = [] as Array[int]
	GameState.last_advance_refusal = GameState.ADVANCE_REFUSAL_NONE
	GameState.floor_divergence_floor = 0
	GameState.floor_divergence_local_hash = 0
	GameState.floor_divergence_host_hash = 0
	NetworkManager.disconnect_all()


func _on_floor_changed(floor_index: int, biome: Resource) -> void:
	_floors.append({
		"floor_index": floor_index,
		"biome_id": FloorGeneratorStub.biome_id_of(biome),
	})


func _on_layout_requested(floor_index: int) -> void:
	_layout_requests.append(floor_index)


# --- the RPC contract -------------------------------------------------------

func test_floor_ready_exists_as_the_spec_rpc() -> void:
	assert_true(NetworkManager.has_method("floor_ready"), "NetworkManager.floor_ready exists")


func test_floor_ready_is_authority_call_local_reliable() -> void:
	var config: Dictionary = _rpc_config(&"floor_ready")
	assert_false(config.is_empty(), "floor_ready is declared with @rpc")
	assert_eq(config.get("rpc_mode"), MultiplayerAPI.RPC_MODE_AUTHORITY, "host -> clients only")
	assert_eq(config.get("call_local"), true, "the host runs it too")
	assert_eq(config.get("transfer_mode"), MultiplayerPeer.TRANSFER_MODE_RELIABLE)


func test_floor_ready_declares_the_specs_four_arguments() -> void:
	var names: Array[String] = _argument_names(&"floor_ready")
	assert_eq(names, ["seed", "floor_index", "biome_id", "modifiers"] as Array[String])


# --- sender validation ------------------------------------------------------

func test_the_host_accepts_only_its_own_local_floor_ready() -> void:
	NetworkManager.start_solo()
	assert_true(NetworkManager.can_accept_floor_ready(0), "the host's own authority call reports sender 0")
	assert_false(NetworkManager.can_accept_floor_ready(CLIENT_PEER), "a client may not declare a floor")
	assert_false(NetworkManager.can_accept_floor_ready(HOST_PEER), "the host itself does not send one up")


func test_a_client_accepts_only_the_hosts_floor_ready() -> void:
	_become_client()
	assert_true(NetworkManager.can_accept_floor_ready(HOST_PEER), "the host's broadcast is the floor of record")
	assert_false(NetworkManager.can_accept_floor_ready(CLIENT_PEER + 1), "a third peer may not declare a floor")
	assert_false(NetworkManager.can_accept_floor_ready(0), "a client has no local authority call")


func test_a_floor_ready_a_client_calls_locally_is_refused() -> void:
	_become_client()
	NetworkManager.floor_ready(999, 3, 1, [] as Array[int])
	assert_eq(NetworkManager.floor_seed, 0, "the refused call changed nothing")
	assert_null(NetworkManager.last_floor_layout)
	assert_eq(_floors.size(), 0, "and emitted no floor_changed")


# --- local generation -------------------------------------------------------

func test_the_host_generates_the_floor_from_its_own_broadcast() -> void:
	NetworkManager.start_solo()
	NetworkManager.floor_ready(4242, 2, 1, [] as Array[int])
	assert_eq(NetworkManager.floor_seed, 4242)
	assert_not_null(NetworkManager.last_floor_layout, "the host generated the floor too")
	assert_eq(FloorGeneratorSeam.layout_hash_of(NetworkManager.last_floor_layout),
		FloorGeneratorSeam.layout_hash_of(FloorGeneratorSeam.generate(4242, 2, 1, [] as Array[int])),
		"same inputs, same layout hash")
	assert_eq(_floors.size(), 0, "the host already emitted floor_changed from its own run state")


func test_a_client_generates_locally_and_follows_the_hosts_floor() -> void:
	_become_client()
	var layout: RefCounted = NetworkManager.apply_floor_ready(777, 4, 2, [3] as Array[int])
	assert_not_null(layout, "the client generated a layout locally")
	assert_eq(NetworkManager.floor_seed, 777)
	assert_eq(FloorGeneratorSeam.layout_hash_of(layout),
		FloorGeneratorSeam.layout_hash_of(FloorGeneratorSeam.generate(777, 4, 2, [3] as Array[int])))
	assert_eq(GameState.remote_floor_index, 4, "the client recorded the host's floor")
	assert_eq(GameState.remote_floor_modifiers, [3] as Array[int])
	assert_eq(_floors.size(), 1, "and told GameState, so the HUD follows")
	assert_eq(_floors[0]["floor_index"], 4)
	assert_eq(_floors[0]["biome_id"], 2)


func test_game_state_refuses_a_remote_floor_on_the_host() -> void:
	NetworkManager.start_solo()
	assert_false(GameState.apply_remote_floor(4, 2, [] as Array[int]), "the host owns floor state")
	assert_eq(GameState.remote_floor_index, 0)
	assert_eq(_floors.size(), 0)


func test_same_seed_and_floor_agree_and_different_seeds_differ() -> void:
	NetworkManager.start_solo()
	var first: RefCounted = NetworkManager.apply_floor_ready(5150, 3, 1, [] as Array[int])
	var again: RefCounted = NetworkManager.apply_floor_ready(5150, 3, 1, [] as Array[int])
	var other: RefCounted = NetworkManager.apply_floor_ready(5151, 3, 1, [] as Array[int])
	assert_eq(FloorGeneratorSeam.layout_hash_of(first), FloorGeneratorSeam.layout_hash_of(again))
	assert_ne(FloorGeneratorSeam.layout_hash_of(first), FloorGeneratorSeam.layout_hash_of(other))


func test_the_broadcast_floor_ready_is_host_only() -> void:
	_become_client()
	assert_false(NetworkManager.broadcast_floor_ready(1, 1, 1), "only the host declares a floor")
	assert_eq(NetworkManager.floor_seed, 0, "the refused broadcast changed nothing")


func test_disconnect_all_clears_the_floor_sync_state() -> void:
	NetworkManager.start_solo()
	NetworkManager.apply_floor_ready(31337, 5, 1, [] as Array[int])
	assert_eq(NetworkManager.floor_seed, 31337)
	NetworkManager.disconnect_all()
	assert_eq(NetworkManager.floor_seed, 0)
	assert_null(NetworkManager.last_floor_layout)
	assert_eq(NetworkManager.last_floor_modifiers, [] as Array[int])


# --- the --seed plumbing ----------------------------------------------------

func test_the_launch_arg_seed_reaches_the_broadcast() -> void:
	NetworkManager.start_solo()
	var opts := LaunchArgs.parse(PackedStringArray(["--seed=%d" % FORCED_SEED]))
	GameState.forced_seed = opts.run_seed
	GameState.start_run(0, 1, _party([HOST_PEER]))
	assert_eq(GameState.run.seed, FORCED_SEED, "start_run used the launch-arg seed")
	assert_eq(NetworkManager.floor_seed, FORCED_SEED, "and that is the seed floor_ready carried")
	assert_eq(FloorGeneratorSeam.layout_hash_of(NetworkManager.last_floor_layout),
		FloorGeneratorSeam.layout_hash_of(FloorGeneratorSeam.generate(FORCED_SEED, 1, 1, [] as Array[int])),
		"both peers would hash the same floor from it")


func test_a_run_without_a_forced_seed_broadcasts_the_rolled_seed() -> void:
	NetworkManager.start_solo()
	GameState.start_run(0, 1, _party([HOST_PEER]))
	assert_ne(GameState.run.seed, 0, "the host rolled a seed")
	assert_eq(NetworkManager.floor_seed, GameState.run.seed, "the rolled seed is what is broadcast")


func test_next_floor_broadcasts_the_new_floor() -> void:
	NetworkManager.start_solo()
	GameState.forced_seed = FORCED_SEED
	GameState.start_run(0, 1, _party([HOST_PEER]))
	assert_eq(NetworkManager.floor_seed, FORCED_SEED)
	GameState.next_floor()
	var layout: FloorLayout = NetworkManager.last_floor_layout as FloorLayout
	assert_not_null(layout, "floor 2 was generated locally")
	assert_eq(layout.floor_index, 2, "floor 2 went out on the same run seed")
	assert_eq(NetworkManager.floor_seed, FORCED_SEED, "the run seed did not change")


func test_the_broadcast_carries_the_floors_biome() -> void:
	NetworkManager.start_solo()
	GameState.forced_seed = FORCED_SEED
	GameState.start_run(0, 6, _party([HOST_PEER]))
	assert_eq(GameState.run.biome_index, 2, "floor 6 is biome 2")
	assert_eq(FloorGeneratorSeam.layout_hash_of(NetworkManager.last_floor_layout),
		FloorGeneratorSeam.layout_hash_of(FloorGeneratorSeam.generate(FORCED_SEED, 6, 2, [] as Array[int])),
		"generation used the biome the broadcast named")


# --- the layout hash assertion (W3-B3b) -------------------------------------

func test_layout_asserted_exists_as_the_spec_broadcast() -> void:
	assert_true(NetworkManager.has_method("layout_asserted"), "NetworkManager.layout_asserted exists")


func test_layout_asserted_is_authority_call_local_reliable() -> void:
	var config: Dictionary = _rpc_config(&"layout_asserted")
	assert_false(config.is_empty(), "layout_asserted is declared with @rpc")
	assert_eq(config.get("rpc_mode"), MultiplayerAPI.RPC_MODE_AUTHORITY, "host -> clients only")
	assert_eq(config.get("call_local"), true, "the host runs it too")
	assert_eq(config.get("transfer_mode"), MultiplayerPeer.TRANSFER_MODE_RELIABLE)
	assert_eq(_argument_names(&"layout_asserted"), ["layout_hash"] as Array[String])


func test_request_floor_layout_is_a_sender_validated_client_request() -> void:
	var config: Dictionary = _rpc_config(&"request_floor_layout")
	assert_false(config.is_empty(), "request_floor_layout is declared with @rpc")
	assert_eq(config.get("rpc_mode"), MultiplayerAPI.RPC_MODE_ANY_PEER, "clients ask")
	assert_eq(config.get("call_local"), false, "the caller does not run it locally")
	assert_eq(config.get("transfer_mode"), MultiplayerPeer.TRANSFER_MODE_RELIABLE)
	assert_eq(_argument_names(&"request_floor_layout"), ["floor_index"] as Array[String])


func test_the_floor_layout_reply_is_an_authority_broadcast() -> void:
	var config: Dictionary = _rpc_config(&"floor_layout")
	assert_false(config.is_empty(), "floor_layout is declared with @rpc")
	assert_eq(config.get("rpc_mode"), MultiplayerAPI.RPC_MODE_AUTHORITY, "only the host sends a layout")
	assert_eq(config.get("call_local"), true)
	assert_eq(config.get("transfer_mode"), MultiplayerPeer.TRANSFER_MODE_RELIABLE)


func test_the_floor_broadcast_sender_rule_covers_the_assertion() -> void:
	NetworkManager.start_solo()
	assert_true(NetworkManager.can_accept_floor_broadcast(0), "the host's own local broadcast")
	assert_false(NetworkManager.can_accept_floor_broadcast(CLIENT_PEER), "a client may not assert a hash")
	_become_client()
	assert_true(NetworkManager.can_accept_floor_broadcast(HOST_PEER), "the host's hash is the one to compare")
	assert_false(NetworkManager.can_accept_floor_broadcast(CLIENT_PEER + 1), "a third peer asserts nothing")
	assert_false(NetworkManager.can_accept_floor_broadcast(0), "a client has no local authority call")


func test_the_host_serves_only_a_remote_clients_layout_request() -> void:
	NetworkManager.start_solo()
	assert_true(NetworkManager.can_serve_floor_layout_request(CLIENT_PEER), "a client's request is served")
	assert_false(NetworkManager.can_serve_floor_layout_request(0), "a direct local call is not a client's request")
	_become_client()
	assert_false(NetworkManager.can_serve_floor_layout_request(CLIENT_PEER + 1), "a client serves nobody")


func test_the_host_hashes_the_layout_it_asserts() -> void:
	NetworkManager.start_solo()
	NetworkManager.broadcast_floor_ready(4242, 2, 1, [] as Array[int])
	assert_eq(NetworkManager.last_floor_index, 2, "the asserted hash names its floor")
	assert_eq(NetworkManager.last_floor_hash,
		FloorGeneratorSeam.layout_hash_of(FloorGeneratorSeam.generate(4242, 2, 1, [] as Array[int])),
		"the host asserts the hash of the layout it generated")


func test_agreeing_hashes_log_agreement_and_change_nothing() -> void:
	_become_client()
	var layout: RefCounted = NetworkManager.apply_floor_ready(777, 4, 2, [3] as Array[int])
	var local_hash: int = FloorGeneratorSeam.layout_hash_of(layout)
	assert_eq(_floors.size(), 1, "the client followed the host's floor")
	assert_true(NetworkManager.apply_layout_assertion(local_hash), "the host asserted the same hash")
	assert_eq(NetworkManager.last_floor_hash, local_hash, "the peer's own hash stands")
	assert_same(NetworkManager.last_floor_layout, layout, "nothing was regenerated")
	assert_eq(_layout_requests, [] as Array[int], "an agreement asks the host for nothing")
	assert_false(GameState.has_floor_divergence(), "and records no divergence")
	assert_eq(_floors.size(), 1, "and does not announce the floor a second time")


func test_a_mismatch_logs_an_error_and_requests_the_hosts_layout() -> void:
	_become_client()
	var layout: RefCounted = NetworkManager.apply_floor_ready(777, 4, 2, [] as Array[int])
	var local_hash: int = FloorGeneratorSeam.layout_hash_of(layout)
	var host_hash: int = local_hash + 1
	assert_false(NetworkManager.apply_layout_assertion(host_hash), "a different hash fails the assertion")
	assert_push_error("layout hash mismatch")
	assert_true(GameState.has_floor_divergence(), "the divergence is recorded, not only logged")
	assert_eq(GameState.floor_divergence_floor, 4)
	assert_eq(GameState.floor_divergence_local_hash, local_hash)
	assert_eq(GameState.floor_divergence_host_hash, host_hash)
	assert_eq(_layout_requests, [4] as Array[int], "the client asked the host for its layout")
	assert_same(NetworkManager.last_floor_layout, layout, "the mismatch does not regenerate the floor")
	assert_true(NetworkManager.is_active, "and leaves the session alive")
	assert_eq(_floors.size(), 1, "the floor is announced once, not twice")


func test_the_hosts_layout_replaces_the_clients_own_after_a_mismatch() -> void:
	_become_client()
	var local: RefCounted = NetworkManager.apply_floor_ready(777, 4, 2, [] as Array[int])
	var local_hash: int = FloorGeneratorSeam.layout_hash_of(local)
	var host_layout: FloorLayout = FloorGenerator.generate(778, 4, BiomeData.for_index(2), [] as Array[int])
	var host_hash: int = host_layout.layout_hash
	assert_ne(host_hash, local_hash, "the two floors differ")
	# The host answers with its own layout, so nothing may be generated here.
	var stub := FloorGeneratorStub.new()
	FloorGeneratorSeam.set_injected_generator(stub)
	var host_wire: Dictionary = FloorGeneratorSeam.serialize_layout(host_layout)
	var applied: RefCounted = NetworkManager.apply_host_layout(4, host_hash, host_wire)
	assert_not_null(applied, "the client applied the host's layout")
	assert_eq(stub.calls.size(), 0, "the fallback applies what the host sent instead of regenerating")
	assert_eq(NetworkManager.last_floor_hash, host_hash, "the client now holds the host's hash")
	assert_eq(FloorGeneratorSeam.layout_hash_of(NetworkManager.last_floor_layout), host_hash)
	var held: FloorLayout = NetworkManager.last_floor_layout as FloorLayout
	assert_not_null(held, "the host's layout replaced the client's")
	assert_eq(held.rooms.size(), host_layout.rooms.size(), "the host's rooms, not the client's")
	assert_eq(held.rooms[0].rect, host_layout.rooms[0].rect)
	assert_eq(NetworkManager.last_floor_index, 4, "the fallback names the floor it corrected")
	assert_eq(NetworkManager.floor_seed, 777, "the run seed is untouched")
	assert_eq(_floors.size(), 1, "applying the fallback does not re-announce the floor")


func test_the_host_does_not_apply_a_layout_it_is_sent() -> void:
	NetworkManager.start_solo()
	NetworkManager.apply_floor_ready(777, 4, 2, [] as Array[int])
	var before: RefCounted = NetworkManager.last_floor_layout
	var before_hash: int = NetworkManager.last_floor_hash
	assert_null(NetworkManager.apply_host_layout(4, 999999, {"layout_hash": 999999}),
		"the host is the layout of record")
	assert_same(NetworkManager.last_floor_layout, before, "the host's layout stands")
	assert_eq(NetworkManager.last_floor_hash, before_hash)
	assert_false(GameState.has_floor_divergence())


func test_an_unusable_layout_reply_leaves_the_client_where_it_was() -> void:
	_become_client()
	var layout: RefCounted = NetworkManager.apply_floor_ready(777, 4, 2, [] as Array[int])
	var local_hash: int = FloorGeneratorSeam.layout_hash_of(layout)
	assert_null(NetworkManager.apply_host_layout(4, 12345, {}), "an empty wire form rebuilds nothing")
	assert_same(NetworkManager.last_floor_layout, layout, "the client keeps its own layout")
	assert_eq(NetworkManager.last_floor_hash, local_hash, "and its own hash")


# --- the layout wire form (the fallback's payload) --------------------------

func test_a_wire_round_trip_preserves_a_layout() -> void:
	var layout: FloorLayout = FloorGenerator.generate(4242, 3, BiomeData.for_index(2), [5] as Array[int])
	var wire: Dictionary = FloorGeneratorSeam.serialize_layout(layout)
	assert_false(wire.is_empty(), "the placeholder has a wire form")
	var rebuilt: RefCounted = FloorGeneratorSeam.deserialize_layout(wire)
	assert_not_null(rebuilt, "and rebuilds from it")
	assert_eq(FloorGeneratorSeam.layout_hash_of(rebuilt), layout.layout_hash, "the hash travels with it")
	var placeholder: FloorLayout = rebuilt as FloorLayout
	assert_not_null(placeholder)
	assert_eq(placeholder.rooms.size(), layout.rooms.size(), "so do the rooms")
	assert_eq(placeholder.modifiers, layout.modifiers)
	assert_eq(placeholder.seed, 4242)
	assert_eq(placeholder.floor_index, 3)
	assert_eq(placeholder.biome_id, 2)


func test_a_layout_with_no_wire_form_rebuilds_nothing() -> void:
	assert_null(FloorGeneratorSeam.deserialize_layout({}), "an empty wire form is not a layout")
	assert_true(FloorGeneratorSeam.serialize_layout(null).is_empty(), "no layout, no wire form")


# --- the generator seam -----------------------------------------------------

func test_the_seam_calls_dev_as_generator_when_one_is_injected() -> void:
	var stub := FloorGeneratorStub.new()
	FloorGeneratorSeam.set_injected_generator(stub)
	var layout: RefCounted = FloorGeneratorSeam.generate(11, 3, 2, [] as Array[int])
	assert_eq(stub.calls.size(), 1, "the seam called the injected generator once")
	assert_eq(stub.calls[0]["run_seed"], 11)
	assert_eq(stub.calls[0]["floor_index"], 3)
	assert_eq(FloorGeneratorStub.biome_id_of(stub.calls[0]["biome"]), 2, "the seam passed a biome resource, as the spec's generate() takes")
	assert_eq(FloorGeneratorSeam.layout_hash_of(layout), FloorGeneratorStub.stub_hash(11, 3),
		"the seam returned the generator's layout, not a stand-in")
	assert_eq(FloorGeneratorSeam.source_of(layout), FloorGeneratorStub.SOURCE)


func test_without_an_injected_generator_the_seam_uses_floor_generation() -> void:
	FloorGeneratorSeam.clear_injected_generator()
	var layout: RefCounted = FloorGeneratorSeam.generate(11, 3, 2, [] as Array[int])
	assert_not_null(layout)
	assert_eq(FloorGeneratorSeam.source_of(layout), FloorLayout.SOURCE)
	assert_eq(FloorGeneratorSeam.layout_hash_of(layout),
		FloorGeneratorSeam.layout_hash_of(FloorGeneratorSeam.generate(11, 3, 2, [] as Array[int])))


func test_the_placeholder_layout_is_deterministic_and_seed_sensitive() -> void:
	var one := FloorLayoutPlaceholder.for_floor(4242, 2, 1, [] as Array[int])
	var same := FloorLayoutPlaceholder.for_floor(4242, 2, 1, [] as Array[int])
	var deeper := FloorLayoutPlaceholder.for_floor(4242, 3, 1, [] as Array[int])
	var other := FloorLayoutPlaceholder.for_floor(4243, 2, 1, [] as Array[int])
	assert_eq(one.layout_hash, same.layout_hash, "same inputs, same layout")
	assert_ne(one.layout_hash, deeper.layout_hash, "a different floor differs")
	assert_ne(one.layout_hash, other.layout_hash, "a different seed differs")
	assert_eq(one.room_count, same.room_count)
	assert_between(one.room_count, FloorLayoutPlaceholder.MIN_ROOMS, FloorLayoutPlaceholder.MAX_ROOMS)


func test_the_modifier_roll_is_deterministic_and_capped() -> void:
	assert_eq(FloorGeneratorSeam.roll_modifiers(4242, 20), FloorGeneratorSeam.roll_modifiers(4242, 20))
	assert_lte(FloorGeneratorSeam.roll_modifiers(4242, 20).size(), FloorGenerator.MAX_MODIFIERS)


# --- helpers ----------------------------------------------------------------

## Puts NetworkManager in the client role a single-process test can drive:
## joined, not hosting. The real client peer id arrives over ENet, so 2 stands
## for it here.
func _become_client() -> void:
	NetworkManager.start_solo()
	NetworkManager.is_host = false
	NetworkManager.local_peer_id = CLIENT_PEER
	NetworkManager.peer_ids = [HOST_PEER, CLIENT_PEER] as Array[int]


func _party(peer_ids: Array[int]) -> Array:
	var party: Array = []
	for peer_id: int in peer_ids:
		party.append(PlayerSpawnInfo.new(peer_id))
	return party


func _rpc_config(method: StringName) -> Dictionary:
	var script: Script = NetworkManager.get_script()
	if script == null or not script.has_method(&"get_rpc_config"):
		return {}
	var config: Variant = script.call(&"get_rpc_config")
	if not config is Dictionary:
		return {}
	var entry: Variant = (config as Dictionary).get(method, {})
	return entry if entry is Dictionary else {}


func _argument_names(method: StringName) -> Array[String]:
	var names: Array[String] = []
	var script: Script = NetworkManager.get_script()
	if script == null:
		return names
	for entry: Dictionary in script.get_script_method_list():
		if str(entry.get("name", "")) != String(method):
			continue
		for arg: Variant in entry.get("args", []):
			names.append(str((arg as Dictionary).get("name", "")))
		break
	return names
