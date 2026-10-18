extends GutTest
## Tests for scenes/main/camera.gd (GameCamera). Owned by player-controller.

const VIEW := Vector2(960, 540)
const WORLD_SCENE := "res://scenes/main/world.tscn"
const PLAYER_SCENE := "res://scenes/player/player.tscn"


func _point(pos: Vector2) -> Node2D:
	var n := Node2D.new()
	n.global_position = pos
	add_child_autofree(n)
	return n


# Pure framing math

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
	var targets: Array[Node2D] = [_point(Vector2(0, 0)), _point(Vector2(100, 0)), _point(Vector2(50, 300))]
	assert_eq(GameCamera.focus_point(targets), Vector2(50, 100))


# In-tree behaviour

func _camera_with(targets: Array[Node2D]) -> GameCamera:
	var cam := GameCamera.new()
	cam.position_smoothing_enabled = false
	add_child_autofree(cam)
	cam.set_targets(targets)
	return cam


func test_frames_two_targets_after_settling() -> void:
	var cam := _camera_with([_point(Vector2(0, 0)), _point(Vector2(1200, 0))])
	cam.update_framing(10.0)
	assert_almost_eq(cam.global_position, Vector2(600, 0), Vector2(0.5, 0.5))
	var expected := GameCamera.fit_zoom(Rect2(Vector2.ZERO, Vector2(1200, 0)), cam.get_viewport_rect().size)
	assert_almost_eq(cam.zoom.x, expected, 0.01)
	assert_almost_eq(cam.zoom.y, expected, 0.01)


func test_view_rect_is_viewport_over_zoom_centered_on_camera() -> void:
	var cam := _camera_with([_point(Vector2(300, 200))])
	cam.update_framing(10.0)
	var rect := cam.view_rect()
	var size := cam.get_viewport_rect().size / cam.zoom.x
	assert_almost_eq(rect.size, size, Vector2(0.5, 0.5))
	assert_almost_eq(rect.get_center(), Vector2(300, 200), Vector2(0.5, 0.5))


func test_clamp_to_view_keeps_point_inside_with_margin() -> void:
	var cam := _camera_with([_point(Vector2.ZERO), _point(Vector2(200, 0))])
	cam.update_framing(10.0)
	var rect := cam.view_rect().grow(-GameCamera.EDGE_PADDING)
	var clamped := cam.clamp_to_view(Vector2(50000, -50000))
	# Rect2.has_point excludes the far edge, and the clamp lands exactly on
	# the padded edge, so compare bounds inclusively.
	assert_almost_eq(clamped.x, rect.end.x, 0.001, "clamped to right padded edge")
	assert_almost_eq(clamped.y, rect.position.y, 0.001, "clamped to top padded edge")
	assert_eq(cam.clamp_to_view(Vector2(100, 0)), Vector2(100, 0), "inside point untouched")


func test_target_count() -> void:
	var cam := _camera_with([_point(Vector2.ZERO), _point(Vector2(1, 1))])
	assert_eq(cam.target_count(), 2)


func test_shake_offsets_within_strength_and_decays_to_zero() -> void:
	var cam := _camera_with([_point(Vector2.ZERO)])
	cam.rng.seed = 1234
	cam.shake(5.0, 0.3)
	cam.update_framing(0.016)
	assert_gt(cam.offset.length(), 0.0, "shaking")
	assert_lte(cam.offset.length(), 5.0 * sqrt(2.0) + 0.001, "bounded by strength")
	cam.update_framing(1.0)
	assert_eq(cam.offset, Vector2.ZERO, "settled")


func test_screen_shake_setting_scales_offset() -> void:
	var cam := _camera_with([_point(Vector2.ZERO)])
	cam.screen_shake = 0.0
	cam.shake(5.0, 0.3)
	cam.update_framing(0.016)
	assert_eq(cam.offset, Vector2.ZERO)


func test_world_camera_tracks_players_container() -> void:
	var world := (load(WORLD_SCENE) as PackedScene).instantiate() as World
	world.debug_test_floor = false
	add_child_autofree(world)
	var player := (load(PLAYER_SCENE) as PackedScene).instantiate() as Player
	player.global_position = Vector2(400, 300)
	world.players.add_child(player)
	var cam := world.camera as GameCamera
	assert_not_null(cam, "World/Camera is a GameCamera")
	cam.update_framing(10.0)
	assert_almost_eq(cam.global_position, Vector2(400, 300), Vector2(0.5, 0.5))
	assert_eq(cam.target_count(), 1)


func test_player_is_clamped_to_view_in_coop() -> void:
	var world := (load(WORLD_SCENE) as PackedScene).instantiate() as World
	world.debug_test_floor = false
	add_child_autofree(world)
	var a := (load(PLAYER_SCENE) as PackedScene).instantiate() as Player
	var b := (load(PLAYER_SCENE) as PackedScene).instantiate() as Player
	world.players.add_child(a)
	world.players.add_child(b)
	b.global_position = Vector2(300, 0)
	var cam := world.camera as GameCamera
	cam.update_framing(10.0)
	a.global_position = Vector2(50000, 0)
	a.clamp_to_camera()
	assert_true(cam.view_rect().has_point(a.global_position), "clamped into view")
