extends GutTest
## Tests for the InputSync / StateSync configuration and the Player-side
## publish, reconcile, and interpolate logic (W1-B9, W1-AB1).
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
	assert_eq(paths.size(), 2, "nothing else goes up")


func test_state_sync_replicates_host_state() -> void:
	var paths := _paths(_player.state_sync)
	for prop: String in ["synced_position", "synced_velocity", "facing_index", "current_anim"]:
		assert_true(paths.has(NodePath(".:" + prop)), prop)
	assert_false(paths.has(NodePath(".:position")), "raw position is never replicated; synced_position is reconciled")


func test_state_sync_sends_pose_every_tick_and_facing_on_change() -> void:
	var cfg := _player.state_sync.replication_config
	assert_eq(cfg.property_get_replication_mode(NodePath(".:synced_position")), SceneReplicationConfig.REPLICATION_MODE_ALWAYS)
	assert_eq(cfg.property_get_replication_mode(NodePath(".:facing_index")), SceneReplicationConfig.REPLICATION_MODE_ON_CHANGE)
	assert_eq(cfg.property_get_replication_mode(NodePath(".:current_anim")), SceneReplicationConfig.REPLICATION_MODE_ON_CHANGE)
	assert_true(cfg.property_get_spawn(NodePath(".:synced_position")), "position is part of the spawn state")


# Host publishing

func test_publish_state_copies_pose_into_synced_fields() -> void:
	_player.position = Vector2(123, 45)
	_player.velocity = Vector2(10, -5)
	_player.publish_state()
	assert_eq(_player.synced_position, Vector2(123, 45))
	assert_eq(_player.synced_velocity, Vector2(10, -5))


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

func test_reconcile_nudges_small_error_without_snapping() -> void:
	_player.position = Vector2.ZERO
	_player.synced_position = Vector2(10, 0)
	_player.reconcile_toward(_player.synced_position, DT)
	assert_gt(_player.position.x, 0.0, "moved toward the host")
	assert_lt(_player.position.x, 10.0, "but not all the way in one frame")


func test_reconcile_snaps_large_error() -> void:
	_player.position = Vector2.ZERO
	_player.synced_position = Vector2(Player.SNAP_DISTANCE + 1.0, 0)
	_player.reconcile_toward(_player.synced_position, DT)
	assert_eq(_player.position, _player.synced_position, "snapped")


func test_reconcile_converges() -> void:
	_player.position = Vector2.ZERO
	var target := Vector2(10, 0)
	for i in 120:
		_player.reconcile_toward(target, DT)
	assert_almost_eq(_player.position, target, Vector2(0.1, 0.1))


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
