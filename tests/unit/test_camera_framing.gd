extends GutTest
## Tests for scenes/main/camera.gd (GameCamera) and the co-op movement clamp.
## Owned by player-controller.

const VIEW := Vector2(960, 540)
const WORLD_SCENE := "res://scenes/main/world.tscn"
const PLAYER_SCENE := "res://scenes/player/player.tscn"
const DT := 1.0 / 60.0


func _spawn_player(parent: Node, pos: Vector2) -> Player:
	var p := (load(PLAYER_SCENE) as PackedScene).instantiate() as Player
	p.global_position = pos
	parent.add_child(p)
	return p


func _players(positions: Array[Vector2]) -> Array[Player]:
	var holder := Node2D.new()
	add_child_autofree(holder)
	var result: Array[Player] = []
	for pos: Vector2 in positions:
		result.append(_spawn_player(holder, pos))
	return result


func _camera_with(players: Array[Player], smoothing: bool = false) -> GameCamera:
	var cam := GameCamera.new()
	cam.position_smoothing_enabled = smoothing
	add_child_autofree(cam)
	cam.make_current()
	cam.set_targets(players)
	return cam


func _world_with(count: int, spread: float) -> World:
	var world := (load(WORLD_SCENE) as PackedScene).instantiate() as World
	world.debug_test_floor = false
	add_child_autofree(world)
	for i in count:
		_spawn_player(world.players, Vector2(i * spread, 0))
	world.camera.make_current()
	return world


# Pure framing math on positions (deterministic, shared with the clamp)

func test_single_target_uses_full_zoom() -> void:
	assert_eq(GameCamera.fit_zoom(Rect2(Vector2(100, 100), Vector2.ZERO), VIEW), 1.0)


func test_small_spread_stays_at_full_zoom() -> void:
	assert_eq(GameCamera.fit_zoom(Rect2(Vector2.ZERO, Vector2(400, 100)), VIEW), 1.0)


func test_wide_spread_zooms_out_with_margin() -> void:
	# 1200 wide + 96 margin each side = 1392; 960 / 1392 = 0.6897
	assert_almost_eq(GameCamera.fit_zoom(Rect2(Vector2.ZERO, Vector2(1200, 100)), VIEW), 0.6897, 0.001)


func test_tall_spread_uses_the_tighter_axis() -> void:
	# 500 tall + 192 = 692; 540 / 692 = 0.7803
	assert_almost_eq(GameCamera.fit_zoom(Rect2(Vector2.ZERO, Vector2(100, 500)), VIEW), 0.7803, 0.001)


func test_zoom_never_goes_below_min() -> void:
	assert_eq(GameCamera.fit_zoom(Rect2(Vector2.ZERO, Vector2(4000, 4000)), VIEW), GameCamera.MIN_ZOOM)


func test_focus_point_is_the_centroid() -> void:
	var positions: Array[Vector2] = [Vector2(0, 0), Vector2(100, 0), Vector2(50, 300)]
	assert_eq(GameCamera.focus_point(positions), Vector2(50, 100))


func test_bounds_of_positions() -> void:
	var positions: Array[Vector2] = [Vector2(10, 20), Vector2(-30, 5), Vector2(0, 100)]
	assert_eq(GameCamera.bounds_of(positions), Rect2(Vector2(-30, 5), Vector2(40, 95)))


func test_coop_bounds_is_the_design_view_minus_padding_around_the_centroid() -> void:
	var positions: Array[Vector2] = [Vector2(0, 0), Vector2(200, 0)]
	var rect := GameCamera.coop_bounds(positions)
	# Spread 200 fits at zoom 1: 960x540 view centered on (100, 0), padded 24.
	assert_almost_eq(rect.get_center(), Vector2(100, 0), Vector2(0.001, 0.001))
	assert_almost_eq(rect.size, VIEW - Vector2.ONE * GameCamera.EDGE_PADDING * 2.0, Vector2(0.001, 0.001))


func test_coop_bounds_grows_when_players_spread() -> void:
	var near: Array[Vector2] = [Vector2(0, 0), Vector2(200, 0)]
	var far: Array[Vector2] = [Vector2(0, 0), Vector2(1200, 0)]
	assert_gt(GameCamera.coop_bounds(far).size.x, GameCamera.coop_bounds(near).size.x)


func test_coop_bounds_ignores_camera_state() -> void:
	# Pure function of positions: two calls with a camera in any state agree.
	var positions: Array[Vector2] = [Vector2(0, 0), Vector2(900, 300)]
	var before := GameCamera.coop_bounds(positions)
	var cam := _camera_with(_players(positions))
	cam.zoom = Vector2(0.7, 0.7)
	cam.global_position = Vector2(-5000, 0)
	assert_eq(GameCamera.coop_bounds(positions), before)


# In-tree behaviour

func test_frames_two_players_after_settling() -> void:
	var cam := _camera_with(_players([Vector2(0, 0), Vector2(1200, 0)]))
	cam.update_framing(10.0)
	assert_almost_eq(cam.global_position, Vector2(600, 0), Vector2(0.5, 0.5))
	var expected := GameCamera.fit_zoom(Rect2(Vector2.ZERO, Vector2(1200, 0)), cam.get_viewport_rect().size)
	assert_almost_eq(cam.zoom.x, expected, 0.01)
	assert_almost_eq(cam.zoom.y, expected, 0.01)


func test_set_targets_accepts_typed_player_array() -> void:
	var players := _players([Vector2.ZERO, Vector2(10, 10)])
	var cam := _camera_with(players)
	assert_eq(cam.target_count(), 2)


func test_view_rect_follows_screen_center_not_target_position() -> void:
	var cam := _camera_with(_players([Vector2(300, 200)]), true)
	cam.global_position = Vector2(300, 200)
	cam.reset_smoothing()
	cam.update_framing(DT)
	var rect := cam.view_rect()
	var size := cam.get_viewport_rect().size / cam.zoom.x
	assert_almost_eq(rect.size, size, Vector2(0.5, 0.5))
	assert_almost_eq(rect.get_center(), cam.get_screen_center_position(), Vector2(0.5, 0.5))


func test_view_rect_with_smoothing_lags_behind_a_jump() -> void:
	var players := _players([Vector2.ZERO])
	var cam := _camera_with(players, true)
	cam.reset_smoothing()
	await wait_process_frames(1)
	players[0].global_position = Vector2(2000, 0)
	await wait_process_frames(1)
	# The node has jumped, the screen has not caught up yet.
	assert_lt(cam.view_rect().get_center().x, 2000.0, "view_rect reports where the screen is, not the target")


func test_shake_offsets_within_max_and_decays_to_zero() -> void:
	var cam := _camera_with(_players([Vector2.ZERO]))
	cam.rng.seed = 1234
	cam.shake(5.0, 0.3)
	cam.update_framing(DT)
	assert_gt(cam.offset.length(), 0.0, "shaking")
	assert_lte(cam.offset.length(), GameCamera.MAX_SHAKE_PX * sqrt(2.0) + 0.001, "bounded")
	cam.update_framing(1.0)
	assert_eq(cam.offset, Vector2.ZERO, "settled")


func test_shake_accumulates_trauma_instead_of_taking_the_max() -> void:
	var cam := _camera_with(_players([Vector2.ZERO]))
	cam.shake(3.0, 1.0)
	var single := cam.trauma
	cam.shake(3.0, 1.0)
	assert_gt(cam.trauma, single, "second hit adds trauma")
	assert_lte(cam.trauma, 1.0, "capped")


func test_screen_shake_setting_scales_offset() -> void:
	var cam := _camera_with(_players([Vector2.ZERO]))
	cam.screen_shake = 0.0
	cam.shake(5.0, 0.3)
	cam.update_framing(DT)
	assert_eq(cam.offset, Vector2.ZERO)


func test_idle_shake_does_not_clobber_offset() -> void:
	var cam := _camera_with(_players([Vector2.ZERO]))
	cam.offset = Vector2(3, 3)
	cam.update_framing(DT)
	assert_eq(cam.offset, Vector2(3, 3), "offset left alone when not shaking")


func test_world_camera_tracks_players_container() -> void:
	var world := _world_with(1, 0.0)
	var player := world.players.get_child(0) as Player
	player.global_position = Vector2(400, 300)
	var cam := world.camera
	cam.update_framing(10.0)
	assert_almost_eq(cam.global_position, Vector2(400, 300), Vector2(0.5, 0.5))
	assert_eq(cam.target_count(), 1)


# Co-op movement clamp through the real Move state

func test_solo_player_is_never_clamped() -> void:
	var world := _world_with(1, 0.0)
	var a := world.players.get_child(0) as Player
	a.move_input = Vector2(1, 0)
	for i in 300:
		a.state_machine.physics_update(DT)
	assert_gt(a.global_position.x, VIEW.x * 0.5, "ran well past where a co-op clamp would stop")


func test_coop_player_cannot_leave_the_shared_frame() -> void:
	# At MIN_ZOOM the padded edge sits about 1850 px from a stationary
	# partner, so run long enough to reach it (120 px/s).
	var world := _world_with(2, 300.0)
	var a := world.players.get_child(0) as Player
	var b := world.players.get_child(1) as Player
	a.move_input = Vector2(1, 0)
	for i in 1200:
		a.state_machine.physics_update(DT)
	var positions: Array[Vector2] = [a.global_position, b.global_position]
	var rect := GameCamera.coop_bounds(positions)
	assert_lte(a.global_position.x, rect.end.x + 0.001, "held at the padded edge")
	assert_gt(a.global_position.x, b.global_position.x, "still moved toward the edge")


func test_clamp_limits_velocity_rather_than_teleporting() -> void:
	var world := _world_with(2, 300.0)
	var a := world.players.get_child(0) as Player
	a.move_input = Vector2(1, 0)
	for i in 1200:
		a.state_machine.physics_update(DT)
	assert_almost_eq(a.velocity.x, 0.0, 0.5, "pinned at the edge means no leftover velocity")
