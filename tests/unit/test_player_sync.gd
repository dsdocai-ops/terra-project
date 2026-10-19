extends GutTest
## Tests for the InputSync / StateSync configuration and the Player-side
## publish, tick-acknowledged reconcile, and interpolate logic (W1-B9, W1-AB1).
## Owned by networking (PR into player.tscn, Alex reviews).

const PLAYER_SCENE := "res://scenes/player/player.tscn"
const DT := 1.0 / 60.0

var _player: Player


func before_each() -> void:
	_player = (load(PLAYER_SCENE) as PackedScene).instantiate() as Player
	add_child_autofree(_player)


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
