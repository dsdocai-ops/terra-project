extends GutTest
## Tests for the relic pick flow: `request_pick_relic`, `relic_choice_offered`,
## `relic_picked`, the host attach and the relic codex (SPEC-relics "Shrine
## flow", "Codex"; SPEC-networking "RPC conventions"; W4-B5, PLAN G10 / raw
## goals G30 + G31). Owned by relics.
##
## The rule this file pins down, in the spec's own order:
##  * a client's `request_pick_relic(index)` is validated by the host against
##    **the offer that peer actually received** and the room state (`GameState.run`
##    live, the shrine still present); a bad index, a peer with no offer, a
##    direct local call (sender 0) and a client-shaped peer are all refused;
##  * on success the host resolves the id to its `RelicData`, attaches it through
##    the player's real `EffectHost.add()` (so its tags appear in `list_tags()`),
##    appends the id to the peer's `RunPlayerState.relics` and emits
##    `Events.relic_picked` exactly once;
##  * a picked offer is consumed, so the same offer cannot be taken twice;
##  * the codex records every relic **seen** — offered and picked — in
##    `SaveManager.profile.codex.relics`, and picking does not double-record.
##
## The RPC declarations are `NetworkManager`'s (the shrine node is spawned by the
## host's populator, so a client never holds one to carry the call). The
## client -> host request is `@rpc("any_peer", "call_remote", "reliable")` and
## the host -> everyone broadcasts are `@rpc("authority", "call_local",
## "reliable")`, per SPEC-networking; the test reads those attributes off the
## script rather than trusting the comment.
##
## The host path is driven through `RelicFlow.apply_pick_request(sender, index)`
## — the same seam `request_pick_relic` calls after reading
## `multiplayer.get_remote_sender_id()` — so one process can exercise a real
## client's sender id without a `MultiplayerPeer` (the `apply_*_request` shape
## the revive contract already ships).
##
## after_each clears `RelicFlow`'s pending offers, the codex profile slot, the
## run and the session so no autoload state leaks into the next file (LESSONS).

const HOST_PEER: int = 1
const GUEST_PEER: int = 2
const THIRD_PEER: int = 3
const FORCED_SEED: int = 777

const SHRINE_SCENE_PATH: String = "res://scenes/dungeon/interactables/shrine.tscn"
const RELIC_FLOW_PATH: String = "res://scripts/relics/relic_flow.gd"
const EFFECT_HOST_NODE: NodePath = ^"EffectHost"

## The harness gives the acting player a real scene with a StatBlock and an
## EffectHost, exactly as `test_relic_triggers.gd` builds one.
var _harness: EffectHarness = null
var _player: Player = null
var _shrine: Shrine = null
## Every Events.relic_picked this test observed, as {player, relic}.
var _picked: Array[Dictionary] = []
## Every relic_offer_received broadcast this test observed.
var _offers_received: Array[Dictionary] = []


func before_each() -> void:
	RelicFlow.reset()
	SaveManager.profile = null
	GameState.run = null
	GameState.forced_seed = 0
	NetworkManager.start_solo()
	_harness = EffectHarness.new(self)
	_harness.setup()
	_player = _harness.make_player()
	_player.peer_id = GUEST_PEER
	_shrine = _make_shrine()
	_picked.clear()
	_offers_received.clear()
	Events.relic_picked.connect(_on_relic_picked)
	NetworkManager.relic_offer_received.connect(_on_relic_offer_received)


func after_each() -> void:
	if Events.relic_picked.is_connected(_on_relic_picked):
		Events.relic_picked.disconnect(_on_relic_picked)
	if NetworkManager.relic_offer_received.is_connected(_on_relic_offer_received):
		NetworkManager.relic_offer_received.disconnect(_on_relic_offer_received)
	RelicFlow.reset()
	SaveManager.profile = null
	GameState.run = null
	GameState.forced_seed = 0
	NetworkManager.disconnect_all()
	_player = null
	_shrine = null
	_harness = null


func _on_relic_picked(player: Player, relic: RelicData) -> void:
	_picked.append({"player": player, "relic": relic})


func _on_relic_offer_received(peer_id: int, ids: Array[StringName]) -> void:
	_offers_received.append({"peer_id": peer_id, "ids": ids})


func _make_shrine() -> Shrine:
	var packed: PackedScene = load(SHRINE_SCENE_PATH) as PackedScene
	assert_not_null(packed, "%s loads" % SHRINE_SCENE_PATH)
	if packed == null:
		return null
	var shrine: Shrine = packed.instantiate() as Shrine
	add_child_autofree(shrine)
	return shrine


func _party(peer_ids: Array[int]) -> Array[PlayerSpawnInfo]:
	var party: Array[PlayerSpawnInfo] = []
	for peer_id: int in peer_ids:
		party.append(PlayerSpawnInfo.new(peer_id))
	return party


func _start_run(peer_ids: Array[int]) -> void:
	GameState.forced_seed = FORCED_SEED
	GameState.start_run(0, 2, _party(peer_ids))
	assert_not_null(GameState.run, "the run is live")


func _host() -> void:
	NetworkManager.start_solo()
	assert_true(NetworkManager.is_host, "the test session is a host")


func _become_client() -> void:
	NetworkManager.is_host = false


## Offers the shrine's three to the acting player and returns them.
func _offer_to(player: Player) -> Array[StringName]:
	_shrine.interact(player)
	return RelicFlow.offer_ids(player.peer_id)


func _slice(peer_id: int) -> RunPlayerState:
	return GameState.run.get_player(peer_id) if GameState.run != null else null


func _effect_host() -> EffectHost:
	return _player.get_node_or_null(EFFECT_HOST_NODE) as EffectHost


## The codex's seen relics, read through the profile slot the spec names
## (`profile.codex.relics`) with Object.get so the file compiles before
## save-system's typed `PlayerProfile` lands (week 5).
func _codex_relics() -> Array:
	var profile: RefCounted = SaveManager.profile
	if profile == null:
		return []
	var codex: Variant = profile.get(&"codex")
	if not codex is Dictionary:
		return []
	var seen: Variant = (codex as Dictionary).get("relics", [])
	return seen if seen is Array else []


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


# --- the RPC contract (SPEC-networking "RPC conventions") ------------------


func test_request_pick_relic_is_a_client_to_host_request() -> void:
	var config: Dictionary = _rpc_config(&"request_pick_relic")
	assert_false(config.is_empty(), "request_pick_relic is declared with @rpc")
	assert_eq(config.get("rpc_mode"), MultiplayerAPI.RPC_MODE_ANY_PEER,
		"a client asks the host; the host did not originate the call")
	assert_eq(config.get("call_local"), false, "the caller does not run the host's half")
	assert_eq(config.get("transfer_mode"), MultiplayerPeer.TRANSFER_MODE_RELIABLE,
		"a pick is never dropped")
	assert_eq(_argument_names(&"request_pick_relic"), ["index"] as Array[String],
		"the request carries an index only, never an id or a value the host would trust")


func test_the_broadcasts_are_host_to_everyone_and_run_locally() -> void:
	for method: StringName in [&"relic_choice_offered", &"relic_picked"]:
		var config: Dictionary = _rpc_config(method)
		assert_false(config.is_empty(), "%s is declared with @rpc" % method)
		assert_eq(config.get("rpc_mode"), MultiplayerAPI.RPC_MODE_AUTHORITY,
			"%s may only be sent by the host" % method)
		assert_eq(config.get("call_local"), true, "%s runs for the host's own state too" % method)
		assert_eq(config.get("transfer_mode"), MultiplayerPeer.TRANSFER_MODE_RELIABLE,
			"%s is never dropped" % method)
	assert_true(NetworkManager.has_method(&"request_pick_relic"), "the request exists")
	assert_true(NetworkManager.has_method(&"relic_choice_offered"), "the offer broadcast exists")
	assert_true(NetworkManager.has_method(&"relic_picked"), "the pick broadcast exists")
	assert_true(NetworkManager.has_method(&"send_pick_relic_request"), "and the client-side sender")


func test_the_pick_flow_lives_in_the_relics_module() -> void:
	assert_true(FileAccess.file_exists(RELIC_FLOW_PATH), "%s exists" % RELIC_FLOW_PATH)
	var source: String = FileAccess.get_file_as_string(RELIC_FLOW_PATH)
	assert_true(source.contains("Sync:"), "every stateful script states who owns it and how it syncs")
	assert_true(source.contains("request_pick_relic"),
		"the flow names the request it is the host half of")


# --- the host attach -------------------------------------------------------


func test_a_valid_pick_attaches_the_effect_and_records_the_relic() -> void:
	_host()
	_start_run([HOST_PEER, GUEST_PEER])
	var ids: Array[StringName] = _offer_to(_player)
	assert_eq(ids.size(), Shrine.OFFER_COUNT, "the shrine offered three")
	if ids.is_empty():
		return
	var chosen: StringName = ids[0]
	var host: EffectHost = _effect_host()
	assert_not_null(host, "the acting player carries an EffectHost")
	if host == null:
		return
	assert_true(RelicFlow.apply_pick_request(GUEST_PEER, 0), "the host applies a valid pick")
	assert_true(host.has_effect(chosen), "the relic is attached through EffectHost.add")
	var data: RelicData = RelicFlow.data_for(chosen)
	assert_not_null(data, "%s resolves to its .tres" % chosen)
	if data == null:
		return
	for tag: StringName in data.tags:
		assert_true(host.list_tags().has(tag), "%s's tag %s is in list_tags()" % [chosen, tag])
	var slice: RunPlayerState = _slice(GUEST_PEER)
	assert_not_null(slice, "the picker's run slice exists")
	if slice != null:
		assert_true(slice.relics.has(chosen), "the id is appended to RunPlayerState.relics")
	assert_eq(_picked.size(), 1, "relic_picked fires exactly once")
	if not _picked.is_empty():
		assert_eq(_picked[0]["player"], _player, "the event names the picker")
		assert_eq((_picked[0]["relic"] as RelicData).id, chosen, "the event names the relic")


func test_a_second_pick_of_the_same_offer_is_refused() -> void:
	_host()
	_start_run([HOST_PEER, GUEST_PEER])
	var ids: Array[StringName] = _offer_to(_player)
	assert_eq(ids.size(), Shrine.OFFER_COUNT, "the shrine offered three")
	assert_true(RelicFlow.apply_pick_request(GUEST_PEER, 0), "the first pick applies")
	assert_false(RelicFlow.apply_pick_request(GUEST_PEER, 1), "the offer is consumed by the pick")
	assert_eq(RelicFlow.last_refusal, RelicFlow.REFUSAL_NO_OFFER, "there is no offer left to pick from")
	var slice: RunPlayerState = _slice(GUEST_PEER)
	if slice != null:
		assert_eq(slice.relics.size(), 1, "exactly one relic was taken")
	assert_eq(_picked.size(), 1, "the event fired once, not twice")


# --- the host's refusals ---------------------------------------------------


func test_a_bad_index_is_refused() -> void:
	_host()
	_start_run([HOST_PEER, GUEST_PEER])
	_offer_to(_player)
	assert_false(RelicFlow.apply_pick_request(GUEST_PEER, Shrine.OFFER_COUNT),
		"an index past the offer is refused")
	assert_eq(RelicFlow.last_refusal, RelicFlow.REFUSAL_BAD_INDEX)
	assert_false(RelicFlow.apply_pick_request(GUEST_PEER, -1), "a negative index is refused")
	assert_eq(RelicFlow.last_refusal, RelicFlow.REFUSAL_BAD_INDEX)
	assert_true(_picked.is_empty(), "nothing was picked")
	assert_eq(_effect_host().effect_count(), 0, "nothing was attached")


func test_a_peer_with_no_offer_is_refused() -> void:
	_host()
	_start_run([HOST_PEER, GUEST_PEER, THIRD_PEER])
	_offer_to(_player)
	assert_false(RelicFlow.apply_pick_request(THIRD_PEER, 0), "a peer the shrine never offered to cannot pick")
	assert_eq(RelicFlow.last_refusal, RelicFlow.REFUSAL_NO_OFFER)


func test_a_direct_local_call_is_not_a_clients_request() -> void:
	_host()
	_start_run([HOST_PEER, GUEST_PEER])
	_offer_to(_player)
	# `request_pick_relic` read `multiplayer.get_remote_sender_id()`; a direct
	# local call reports 0 everywhere, which is not a client's request.
	NetworkManager.request_pick_relic(0)
	assert_eq(RelicFlow.last_refusal, RelicFlow.REFUSAL_NOT_A_REQUEST,
		"sender 0 is not a client's request")
	assert_true(_picked.is_empty(), "an unvalidated local call attaches nothing")


func test_a_client_applies_nothing_itself() -> void:
	_host()
	_start_run([HOST_PEER, GUEST_PEER])
	_offer_to(_player)
	_become_client()
	assert_false(RelicFlow.apply_pick_request(GUEST_PEER, 0), "only the host attaches a relic")
	assert_eq(RelicFlow.last_refusal, RelicFlow.REFUSAL_NOT_HOST)
	assert_eq(_effect_host().effect_count(), 0, "a client holds no effect instances")


func test_the_room_state_is_part_of_the_validation() -> void:
	_host()
	_start_run([HOST_PEER, GUEST_PEER])
	_offer_to(_player)
	GameState.run = null
	assert_false(RelicFlow.apply_pick_request(GUEST_PEER, 0), "no live run, nothing to pick into")
	assert_eq(RelicFlow.last_refusal, RelicFlow.REFUSAL_NO_RUN)


func test_a_shrine_that_is_gone_refuses_the_pick() -> void:
	_host()
	_start_run([HOST_PEER, GUEST_PEER])
	_offer_to(_player)
	_shrine.free()
	_shrine = null
	assert_false(RelicFlow.apply_pick_request(GUEST_PEER, 0), "the offer's room is gone")
	assert_eq(RelicFlow.last_refusal, RelicFlow.REFUSAL_SHRINE_GONE)


# --- the codex (SPEC-relics "Codex") ---------------------------------------


func test_an_offer_records_every_seen_id_in_the_codex() -> void:
	_host()
	_start_run([HOST_PEER, GUEST_PEER])
	var ids: Array[StringName] = _offer_to(_player)
	assert_not_null(SaveManager.profile, "the codex slot has a profile holder")
	var seen: Array = _codex_relics()
	assert_eq(seen.size(), ids.size(), "every offered id is recorded, offered and not only picked")
	for id: StringName in ids:
		assert_true(seen.has(id), "offered %s is in profile.codex.relics" % id)


func test_picking_does_not_double_record_in_the_codex() -> void:
	_host()
	_start_run([HOST_PEER, GUEST_PEER])
	var ids: Array[StringName] = _offer_to(_player)
	assert_true(RelicFlow.apply_pick_request(GUEST_PEER, 0), "a pick applies")
	var seen: Array = _codex_relics()
	assert_eq(seen.size(), ids.size(), "the codex did not grow when the offer was picked")
	assert_eq(seen.count(ids[0]), 1, "the picked id is recorded once")


func test_the_codex_is_idempotent_across_two_offers_of_the_same_id() -> void:
	_host()
	_start_run([HOST_PEER, GUEST_PEER])
	var ids: Array[StringName] = _offer_to(_player)
	# A second shrine offers the same seeded three; nothing is recorded twice.
	var other: Shrine = _make_shrine()
	other.interact(_player)
	assert_eq(_codex_relics().size(), ids.size(), "seeing the same relics again adds nothing")


# --- the wire halves -------------------------------------------------------


func test_the_host_routes_the_offer_to_the_offered_peer() -> void:
	_host()
	_start_run([HOST_PEER, GUEST_PEER])
	var ids: Array[StringName] = _offer_to(_player)
	assert_false(NetworkManager.route_relic_choice_offered(GUEST_PEER, ids),
		"a solo host has no remote peer to send to")
	assert_true(NetworkManager.route_relic_choice_offered(HOST_PEER, ids) == false,
		"the offering peer itself is not re-sent its own offer")


func test_the_receiving_half_of_the_offer_emits_it_for_the_ui() -> void:
	_host()
	_start_run([HOST_PEER, GUEST_PEER])
	var ids: Array[StringName] = _offer_to(_player)
	assert_true(NetworkManager.apply_relic_offer(GUEST_PEER, ids),
		"a client applies the host's offer broadcast")
	assert_eq(_offers_received.size(), 1, "the offer reaches the UI's listener once")
	if not _offers_received.is_empty():
		assert_eq(int(_offers_received[0]["peer_id"]), GUEST_PEER)
		assert_eq(_offers_received[0]["ids"], ids, "the ids are carried unchanged")


func test_the_receiving_half_of_the_pick_emits_relic_picked() -> void:
	_host()
	_start_run([HOST_PEER, GUEST_PEER])
	var ids: Array[StringName] = _offer_to(_player)
	var chosen: StringName = ids[0]
	assert_true(NetworkManager.apply_relic_pick_broadcast(GUEST_PEER, chosen),
		"a peer applies the host's pick broadcast")
	assert_eq(_picked.size(), 1, "the pick reaches the presentation bus once")
	if not _picked.is_empty():
		assert_eq((_picked[0]["relic"] as RelicData).id, chosen)


func test_the_client_sender_refuses_a_session_with_no_remote_host() -> void:
	_host()
	_start_run([HOST_PEER, GUEST_PEER])
	_offer_to(_player)
	_become_client()
	# A solo-shaped session still reports multiplayer.is_server(), so there is no
	# remote host to send to and the request is recorded rather than faked.
	assert_false(NetworkManager.send_pick_relic_request(0),
		"a session with no remote host sends nothing")
	assert_true(RelicFlow.has_offer(GUEST_PEER),
		"the offer is untouched by a request that never left")
