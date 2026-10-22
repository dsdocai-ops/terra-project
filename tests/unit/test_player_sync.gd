extends GutTest
## Tests for the InputSync / StateSync configuration and the Player-side
## publish, tick-acknowledged reconcile, and interpolate logic (W1-B9, W1-AB1).
## Owned by networking (PR into player.tscn, Dev A reviews).

const PLAYER_SCENE := "res://scenes/player/player.tscn"
const DT := 1.0 / 60.0

## The peer ids a single-process test uses for the two roles. The real ids
## arrive over ENet; 1 is always the host (NetworkManager.HOST_PEER_ID).
const HOST_PEER := 1
const CLIENT_PEER := 2

var _player: Player


func before_each() -> void:
	_player = (load(PLAYER_SCENE) as PackedScene).instantiate() as Player
	add_child_autofree(_player)


## NetworkManager is an autoload, so everything these tests write into it has to
## be given back: a session left active, or a player left in the registry, would
## leak into the next test file (LESSONS: autoload state bleeds across GUT files).
func after_each() -> void:
	NetworkManager.disconnect_all()


func _paths(sync: MultiplayerSynchronizer) -> Array[NodePath]:
	return sync.replication_config.get_properties()


# Replication configs

func test_both_synchronizers_root_at_the_player() -> void:
	assert_eq(_player.input_sync.root_path, NodePath(".."))
	assert_eq(_player.state_sync.root_path, NodePath(".."))


func test_input_sync_replicates_input_only() -> void:
	var paths := _paths(_player.input_sync)
	assert_true(paths.has(NodePath(".:move_input")), "move_input")
	assert_true(paths.has(NodePath(".:aim_position")), "aim_position")
	assert_true(paths.has(NodePath(".:input_tick")), "input_tick")
	assert_eq(paths.size(), 3, "nothing else goes up")


func test_state_sync_replicates_host_state() -> void:
	var paths := _paths(_player.state_sync)
	for prop: String in ["synced_position", "synced_velocity", "acked_input_tick", "facing_index", "current_anim"]:
		assert_true(paths.has(NodePath(".:" + prop)), prop)
	assert_false(paths.has(NodePath(".:position")), "raw position is never replicated; synced_position is reconciled")


func test_state_sync_sends_pose_every_tick_and_facing_on_change() -> void:
	var cfg := _player.state_sync.replication_config
	assert_eq(cfg.property_get_replication_mode(NodePath(".:synced_position")), SceneReplicationConfig.REPLICATION_MODE_ALWAYS)
	assert_eq(cfg.property_get_replication_mode(NodePath(".:facing_index")), SceneReplicationConfig.REPLICATION_MODE_ON_CHANGE)
	assert_eq(cfg.property_get_replication_mode(NodePath(".:current_anim")), SceneReplicationConfig.REPLICATION_MODE_ON_CHANGE)
	assert_true(cfg.property_get_spawn(NodePath(".:synced_position")), "position is part of the spawn state")
	assert_eq(cfg.property_get_replication_mode(NodePath(".:acked_input_tick")), SceneReplicationConfig.REPLICATION_MODE_ALWAYS,
		"the ack travels in the same packet as the pose it describes")
	var input_cfg := _player.input_sync.replication_config
	assert_eq(input_cfg.property_get_replication_mode(NodePath(".:input_tick")), SceneReplicationConfig.REPLICATION_MODE_ALWAYS,
		"the tick travels in the same packet as move_input")


# Host publishing

func test_publish_state_copies_pose_into_synced_fields() -> void:
	_player.position = Vector2(123, 45)
	_player.velocity = Vector2(10, -5)
	_player.publish_state()
	assert_eq(_player.synced_position, Vector2(123, 45))
	assert_eq(_player.synced_velocity, Vector2(10, -5))


func test_host_acks_the_input_tick_it_applied_on_the_last_physics_tick() -> void:
	_player.input_tick = 42
	await wait_physics_frames(1)
	_player.input_tick = 43  # arrived after the tick; not applied yet
	_player.publish_state()
	assert_eq(_player.acked_input_tick, 42)


func test_sync_role_on_the_server_is_host_publishes() -> void:
	assert_true(multiplayer.is_server())
	assert_eq(_player.sync_role(), Player.SyncRole.HOST_PUBLISHES)


func test_only_remote_copies_opt_out_of_tick_interpolation() -> void:
	assert_eq(Player.interpolation_mode_for(Player.SyncRole.HOST_PUBLISHES), Node.PHYSICS_INTERPOLATION_MODE_INHERIT)
	assert_eq(Player.interpolation_mode_for(Player.SyncRole.LOCAL_PREDICTS), Node.PHYSICS_INTERPOLATION_MODE_INHERIT)
	assert_eq(Player.interpolation_mode_for(Player.SyncRole.REMOTE_INTERPOLATES), Node.PHYSICS_INTERPOLATION_MODE_OFF,
		"remote copies ease every rendered frame already")
	assert_eq(_player.physics_interpolation_mode, Node.PHYSICS_INTERPOLATION_MODE_INHERIT, "host copy applied on ready")


func test_current_anim_setter_replays_sprite_for_remote_copies() -> void:
	_player.current_anim = "walk"
	assert_eq(_player.sprite.animation, &"walk_s")
	_player.facing_index = 2
	assert_eq(_player.sprite.animation, &"walk_w")


# Client-side reconcile (local prediction) and interpolation (remote copies)

const LAG_TICKS := 6
const WALK_STEP := Vector2(2, 0)


## Walks the local prediction WALK_STEP per tick for `ticks` ticks. The host
## acks each tick LAG_TICKS later with `host_path.call(tick)`.
func _walk_with_lagged_acks(ticks: int, host_path: Callable) -> void:
	_player.position = Vector2.ZERO
	for tick in ticks:
		_player.record_prediction(tick, _player.position)
		if tick >= LAG_TICKS:
			var acked := tick - LAG_TICKS
			_player.reconcile(acked, host_path.call(acked) as Vector2, DT)
		_player.position += WALK_STEP


func test_reconcile_leaves_a_walking_player_alone_when_the_host_agrees() -> void:
	# Regression: the host pose is a round trip old. Comparing it with the
	# present dragged a walking local player back every frame (jitter).
	_walk_with_lagged_acks(60, func(tick: int) -> Vector2: return WALK_STEP * tick)
	assert_eq(_player.position, WALK_STEP * 60, "no correction when every ack matches the prediction")


func test_reconcile_ignores_error_inside_the_deadzone() -> void:
	_player.record_prediction(5, Vector2(10, 0))
	_player.position = Vector2(20, 0)
	_player.reconcile(5, Vector2(10 + Player.RECONCILE_DEADZONE, 0), DT)
	assert_eq(_player.position, Vector2(20, 0))


func test_reconcile_nudges_small_error_without_snapping() -> void:
	_player.record_prediction(5, Vector2(10, 0))
	_player.position = Vector2(20, 0)
	_player.reconcile(5, Vector2(14, 0), DT)
	assert_gt(_player.position.x, 20.0, "moved by the error at the acked tick")
	assert_lt(_player.position.x, 24.0, "but not all of it in one ack")


func test_reconcile_snaps_large_error() -> void:
	_player.record_prediction(5, Vector2(10, 0))
	_player.position = Vector2(20, 0)
	var error := Vector2(Player.SNAP_DISTANCE + 1.0, 0)
	_player.reconcile(5, Vector2(10, 0) + error, DT)
	assert_eq(_player.position, Vector2(20, 0) + error, "present shifted by the full error")


func test_reconcile_converges_on_a_host_that_disagrees() -> void:
	var offset := Vector2(10, 0)
	_walk_with_lagged_acks(240, func(tick: int) -> Vector2: return WALK_STEP * tick + offset)
	var deadzone := Vector2.ONE * Player.RECONCILE_DEADZONE
	assert_almost_eq(_player.position, WALK_STEP * 240 + offset, deadzone, "follows the host path")


func test_reconcile_applies_each_ack_once() -> void:
	_player.record_prediction(5, Vector2(10, 0))
	_player.record_prediction(6, Vector2(12, 0))
	_player.position = Vector2(14, 0)
	_player.reconcile(5, Vector2(14, 0), DT)
	var after_first := _player.position
	_player.reconcile(5, Vector2(14, 0), DT)
	_player.reconcile(4, Vector2(14, 0), DT)
	assert_eq(_player.position, after_first, "a repeated or older ack changes nothing")


func test_reconcile_without_a_prediction_snaps_only_when_far() -> void:
	_player.position = Vector2(20, 0)
	_player.reconcile(3, Vector2(30, 0), DT)
	assert_eq(_player.position, Vector2(20, 0), "unknown tick, small gap: wait for a comparable ack")
	_player.reconcile(4, Vector2(20 + Player.SNAP_DISTANCE + 1.0, 0), DT)
	assert_eq(_player.position, Vector2(20 + Player.SNAP_DISTANCE + 1.0, 0), "unknown tick, gross gap: snap")


func test_prediction_history_is_bounded() -> void:
	for tick in Player.PREDICTION_HISTORY * 3:
		_player.record_prediction(tick, Vector2.ZERO)
	_player.position = Vector2.ZERO
	_player.reconcile(0, Vector2(30, 0), DT)
	assert_eq(_player.position, Vector2.ZERO, "tick 0 was dropped, so there is nothing to compare")


func test_interpolate_moves_remote_copy_smoothly_toward_synced_pose() -> void:
	_player.position = Vector2.ZERO
	_player.interpolate_toward(Vector2(30, 0), DT)
	assert_gt(_player.position.x, 0.0)
	assert_lt(_player.position.x, 30.0)
	for i in 120:
		_player.interpolate_toward(Vector2(30, 0), DT)
	assert_almost_eq(_player.position, Vector2(30, 0), Vector2(0.1, 0.1))


func test_interpolate_snaps_when_far_behind() -> void:
	_player.position = Vector2.ZERO
	_player.interpolate_toward(Vector2(5000, 0), DT)
	assert_eq(_player.position, Vector2(5000, 0))


# Downed state sync and the downed / revived broadcast (W3-B4a)

## SPEC-networking's week 3 row is "downed and revive synced". It asks for two
## things at once, so this section proves both:
##  1. `is_downed` is a replicated StateSync property, so a peer's copy of a
##     downed teammate converges without a message of its own, and
##  2. `NetworkManager.broadcast_player_downed` / `broadcast_player_revived` are
##     the host's authority broadcasts, so the downed and revived *events* reach
##     a client's Events bus and therefore its HUD and its run bookkeeping.
## The RPC bodies are a sender check plus a call to the apply_* function the
## tests drive here, exactly like the floor-sync RPCs; the real client half of
## each is process-to-process and belongs to the two-instance smoke (step 5),
## because a single process cannot report a remote sender id.

func test_state_sync_replicates_the_downed_flag() -> void:
	# The spec names the field `is_downed` (SPEC-player-controller "Interfaces"),
	# and SPEC-networking lists "downed state" among what StateSync carries.
	var paths: Array[NodePath] = _paths(_player.state_sync)
	assert_true(paths.has(NodePath(".:is_downed")), "the downed state is replicated")
	var downed_paths: Array[NodePath] = []
	for path: NodePath in paths:
		if String(path).contains("downed"):
			downed_paths.append(path)
	assert_eq(downed_paths, [NodePath(".:is_downed")] as Array[NodePath],
		"one downed flag, the spec's own field, not a second one beside it")
	var cfg := _player.state_sync.replication_config
	assert_eq(cfg.property_get_replication_mode(NodePath(".:is_downed")), SceneReplicationConfig.REPLICATION_MODE_ON_CHANGE,
		"a down is an edge, so it travels when it changes")
	assert_true(cfg.property_get_spawn(NodePath(".:is_downed")),
		"and it is in the spawn state, so a peer joining mid-run is told at once")


func test_every_replicated_path_resolves_on_the_player() -> void:
	# A path the synchronizer cannot resolve replicates nothing, and says
	# nothing about it: the property has to exist on the node StateSync roots at.
	for path: NodePath in _paths(_player.state_sync):
		var prop := String(path)
		assert_true(prop.begins_with(".:"), prop)
		assert_true(prop.substr(2) in _player, "%s resolves on the player" % prop)
	assert_true("is_downed" in _player)
	assert_false("is_downned" in _player, "a typo would not resolve, so the check above can fail")


func test_a_downed_flag_reaches_this_peers_hud_model() -> void:
	# What step 5 of the two-instance smoke looks at: the receiving peer's own
	# bar has to show the down. The HUD model is fed straight from
	# NetworkManager.players, which is where a broadcast lands the flag.
	_become_client()
	_register(_player, CLIENT_PEER)
	NetworkManager.apply_player_downed(CLIENT_PEER)
	var model := HudModel.new()
	model.bind(_players_for_hud)
	model.refresh(CLIENT_PEER)
	assert_true(model.local_is_downed, "the client's own bar shows the down")
	NetworkManager.apply_player_revived(CLIENT_PEER, HOST_PEER)
	model.refresh(CLIENT_PEER)
	assert_false(model.local_is_downed, "and clears once the host revives")


func test_the_downed_flag_is_host_owned_and_stops_the_downed_player() -> void:
	_player.peer_id = multiplayer.get_unique_id()
	assert_true(_player.simulates, "a standing local player runs its states")
	_player.is_downed = true
	assert_false(_player.simulates, "a downed player cannot move")
	assert_false(_player.state_machine.is_physics_processing(), "its state machine stops with it")
	_player.is_downed = false
	assert_true(_player.simulates, "standing back up resumes it")
	assert_true(_player.state_machine.is_physics_processing())


func test_going_down_emits_the_players_own_downed_signal_once() -> void:
	watch_signals(_player)
	_player.is_downed = true
	assert_signal_emitted(_player, "downed")
	_player.is_downed = true
	assert_signal_emit_count(_player, "downed", 1, "a repeated down is not a second signal")


func test_a_client_takes_the_downed_flag_from_the_hosts_broadcast() -> void:
	_become_client()
	_register(_player, CLIENT_PEER)
	watch_signals(Events)
	assert_true(NetworkManager.apply_player_downed(CLIENT_PEER), "the client applied the host's down")
	assert_true(_player.is_downed, "the replicated flag stands on the client")
	assert_false(_player.simulates, "and the client's copy stops presenting it as standing")


func test_the_down_broadcast_emits_the_bus_event_on_a_client() -> void:
	_become_client()
	_register(_player, CLIENT_PEER)
	watch_signals(Events)
	NetworkManager.apply_player_downed(CLIENT_PEER)
	# The client's HUD and run bookkeeping hear about the down through the same
	# bus signal the host reacted to. (This assertion takes no trailing message:
	# GUT reads its fourth argument as an emission index, not as a label.)
	assert_signal_emitted_with_parameters(Events, "player_downed", [_player])


func test_the_revived_broadcast_clears_the_flag_and_emits_the_bus_event() -> void:
	_become_client()
	_register(_player, CLIENT_PEER)
	_player.is_downed = true
	watch_signals(Events)
	assert_true(NetworkManager.apply_player_revived(CLIENT_PEER, HOST_PEER))
	assert_false(_player.is_downed, "the client's copy stands back up")
	assert_signal_emitted_with_parameters(Events, "player_revived", [_player, NetworkManager.get_player(HOST_PEER)])


func test_a_broadcast_for_an_unknown_player_applies_nothing() -> void:
	_become_client()
	watch_signals(Events)
	assert_false(NetworkManager.apply_player_downed(CLIENT_PEER + 1), "no such player on this peer")
	assert_push_warning("no such player on this peer")
	assert_false(NetworkManager.apply_player_revived(CLIENT_PEER + 1, HOST_PEER))
	assert_signal_not_emitted(Events, "player_downed")
	assert_signal_not_emitted(Events, "player_revived")


# The RPC contract

func test_the_downed_broadcast_is_the_hosts_authority_call() -> void:
	var config: Dictionary = _rpc_config(&"broadcast_player_downed")
	assert_false(config.is_empty(), "broadcast_player_downed is declared with @rpc")
	assert_eq(config.get("rpc_mode"), MultiplayerAPI.RPC_MODE_AUTHORITY, "only the host announces a down")
	assert_eq(config.get("call_local"), true, "the host runs it too")
	assert_eq(config.get("transfer_mode"), MultiplayerPeer.TRANSFER_MODE_RELIABLE, "a down is never dropped")
	assert_eq(_argument_names(&"broadcast_player_downed"), ["peer_id"] as Array[String])


func test_the_revived_broadcast_is_the_hosts_authority_call() -> void:
	var config: Dictionary = _rpc_config(&"broadcast_player_revived")
	assert_false(config.is_empty(), "broadcast_player_revived is declared with @rpc")
	assert_eq(config.get("rpc_mode"), MultiplayerAPI.RPC_MODE_AUTHORITY, "only the host announces a revive")
	assert_eq(config.get("call_local"), true, "the host runs it too")
	assert_eq(config.get("transfer_mode"), MultiplayerPeer.TRANSFER_MODE_RELIABLE)
	assert_eq(_argument_names(&"broadcast_player_revived"), ["peer_id", "by_peer_id"] as Array[String])


func test_the_host_accepts_only_its_own_player_state_broadcast() -> void:
	NetworkManager.start_solo()
	assert_true(NetworkManager.can_accept_host_broadcast(0), "the host's own authority call reports sender 0")
	assert_false(NetworkManager.can_accept_host_broadcast(CLIENT_PEER), "a client may not announce a down")
	_become_client()
	assert_true(NetworkManager.can_accept_host_broadcast(HOST_PEER), "the host's broadcast is the one to apply")
	assert_false(NetworkManager.can_accept_host_broadcast(0), "a client's local call is not the host's")
	assert_false(NetworkManager.can_accept_host_broadcast(CLIENT_PEER + 1), "nor is a third peer's")


func test_the_broadcast_body_refuses_a_local_call_on_a_client() -> void:
	# The accepted branch needs a remote sender id, so this drives the body's
	# one refusal path: a direct local call reports sender 0 everywhere, and the
	# host's broadcast is the only thing a client may apply.
	_become_client()
	_register(_player, CLIENT_PEER)
	watch_signals(Events)
	NetworkManager.broadcast_player_downed(CLIENT_PEER)
	NetworkManager.broadcast_player_revived(CLIENT_PEER, HOST_PEER)
	assert_push_warning("may not be applied on this peer")
	assert_false(_player.is_downed, "an unvalidated down applies nothing")
	assert_signal_not_emitted(Events, "player_downed")
	assert_signal_not_emitted(Events, "player_revived")


# Routing the host's own bus events to the broadcast

func test_network_manager_listens_for_the_hosts_downed_and_revived_events() -> void:
	assert_true(Events.player_downed.is_connected(Callable(NetworkManager, &"_on_player_downed")),
		"the host's down has a route to the broadcast")
	assert_true(Events.player_revived.is_connected(Callable(NetworkManager, &"_on_player_revived")),
		"and so does the revive")


func test_the_router_targets_remote_peers_only() -> void:
	NetworkManager.start_solo()
	assert_eq(NetworkManager.remote_peer_ids(), [] as Array[int], "solo has nobody to tell")
	NetworkManager.peer_ids = [HOST_PEER, CLIENT_PEER, CLIENT_PEER + 1] as Array[int]
	assert_eq(NetworkManager.remote_peer_ids(), [CLIENT_PEER, CLIENT_PEER + 1] as Array[int],
		"the host's own copy is already down: it is never a target")


func test_the_router_is_silent_when_there_is_nobody_to_tell() -> void:
	NetworkManager.start_solo()
	assert_false(NetworkManager.route_player_downed(_player), "a solo host sends nothing")
	assert_false(NetworkManager.route_player_revived(_player, null), "and neither does a solo revive")


func test_the_router_refuses_on_a_client() -> void:
	_become_client()
	assert_false(NetworkManager.route_player_downed(_player))
	assert_push_warning("the host owns downed state")
	assert_false(NetworkManager.route_player_revived(_player, null))
	assert_push_warning("the host owns downed state")


func test_the_router_refuses_an_event_that_names_no_player() -> void:
	NetworkManager.start_solo()
	assert_false(NetworkManager.route_player_downed(null))
	assert_push_warning("named no player")


# helpers

## Puts NetworkManager in the client role a single-process test can drive:
## joined, not hosting. The real client peer id arrives over ENet, so
## CLIENT_PEER stands for it here.
func _become_client() -> void:
	NetworkManager.start_solo()
	NetworkManager.is_host = false
	NetworkManager.local_peer_id = CLIENT_PEER
	NetworkManager.peer_ids = [HOST_PEER, CLIENT_PEER] as Array[int]


## Registers a player with NetworkManager the way PlayerSpawner does once its
## spawn completes, so a broadcast by peer id has a node to land on.
func _register(player: Player, peer_id: int) -> void:
	player.peer_id = peer_id
	NetworkManager.players[peer_id] = player


## The registry the HUD binds to in the game, read through a named method
## because GUT never fires a lambda callback.
func _players_for_hud() -> Dictionary[int, Player]:
	return NetworkManager.players


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
