extends GutTest
## Tests for facing sectors (Facing.index_for) and Move/Idle movement math.
## Owned by player-controller.

const PLAYER_SCENE := "res://scenes/player/player.tscn"
const DT := 1.0 / 60.0

## Screen-space unit vectors for the 8 facings, in Facing.SUFFIXES order:
## s, sw, w, nw, n, ne, e, se. Diagonals follow the tile axes.
const FACING_VECTORS: Array[Vector2] = [
	Vector2(0, 1), Vector2(-32, 16), Vector2(-1, 0), Vector2(-32, -16),
	Vector2(0, -1), Vector2(32, -16), Vector2(1, 0), Vector2(32, 16),
]

var _player: Player


func before_each() -> void:
	_player = (load(PLAYER_SCENE) as PackedScene).instantiate() as Player
	add_child_autofree(_player)


func _step(frames: int) -> void:
	for i in frames:
		_player.state_machine.physics_update(DT)


# Facing.index_for

func _at(degrees: float) -> Vector2:
	return Vector2.RIGHT.rotated(deg_to_rad(degrees))


func test_tables_agree_in_size() -> void:
	assert_eq(Facing.SUFFIXES.size(), 8)
	assert_eq(Facing.CENTERS_DEG.size(), 8)
	assert_eq(Facing.ANGULAR_ORDER.size(), 8)
	assert_eq(Facing.SECTOR_BOUNDS.size(), 8)
	assert_eq(Facing.count(), 8)


func test_exact_directions_map_to_their_index() -> void:
	for i in FACING_VECTORS.size():
		assert_eq(Facing.index_for(FACING_VECTORS[i].normalized()), i, "facing %s" % Facing.suffix(i))


func test_sector_bounds_for_east_wrap_around_zero() -> void:
	var e := Facing.SECTOR_BOUNDS[6]
	assert_almost_eq(e.x, 346.717, 0.01, "lower edge, midway to ne")
	assert_almost_eq(e.y, 13.283, 0.01, "upper edge, midway to se")


func test_sector_boundaries_sit_midway_between_neighbours() -> void:
	# Between e (0 deg) and se (26.565 deg) the boundary is 13.28 deg.
	assert_eq(Facing.index_for(_at(12.0)), 6, "just below boundary is e")
	assert_eq(Facing.index_for(_at(15.0)), 7, "just above boundary is se")
	# Between se (26.565) and s (90) the boundary is 58.28 deg.
	assert_eq(Facing.index_for(_at(57.0)), 7)
	assert_eq(Facing.index_for(_at(60.0)), 0)


func test_boundaries_across_the_zero_degree_wrap() -> void:
	# ne (333.435) and e (0) meet at 346.72 deg.
	assert_eq(Facing.index_for(_at(343.0)), 5, "just below the wrap boundary is ne")
	assert_eq(Facing.index_for(_at(350.0)), 6, "just above it is e")
	assert_eq(Facing.index_for(_at(359.9)), 6)
	assert_eq(Facing.index_for(_at(-5.0)), 6, "negative angles normalise")


func test_hysteresis_keeps_current_sector_near_boundary() -> void:
	var near_boundary := _at(14.5)
	assert_eq(Facing.index_for(near_boundary, 6, 3.0), 6, "stays e within hysteresis")
	assert_eq(Facing.index_for(near_boundary, 7, 3.0), 7, "stays se within hysteresis")
	var well_past := _at(20.0)
	assert_eq(Facing.index_for(well_past, 6, 3.0), 7, "switches once clearly past")


func test_hysteresis_straddling_the_wrap() -> void:
	# ne's upper edge is 346.72; with 3 deg hysteresis it holds until 349.72.
	assert_eq(Facing.index_for(_at(348.0), 5, 3.0), 5, "ne holds just past its edge")
	assert_eq(Facing.index_for(_at(352.0), 5, 3.0), 6, "then gives way to e")
	# e's lower edge is 346.72; from e, 345 deg is still inside hysteresis.
	assert_eq(Facing.index_for(_at(345.0), 6, 3.0), 6, "e holds below its lower edge")
	assert_eq(Facing.index_for(_at(341.0), 6, 3.0), 5, "then gives way to ne")


func test_zero_vector_keeps_current() -> void:
	assert_eq(Facing.index_for(Vector2.ZERO, 3), 3)
	assert_eq(Facing.index_for(Vector2.ZERO), 0)


# Movement

func test_move_reaches_base_speed_within_four_frames() -> void:
	_player.move_input = Vector2(1, 0)
	_step(4)
	assert_almost_eq(_player.velocity.length(), Player.BASE_MOVE_SPEED, 0.5)


func test_first_frame_of_input_already_accelerates() -> void:
	_player.move_input = Vector2(1, 0)
	_step(1)
	assert_eq(_player.state_machine.current_name(), &"Move")
	assert_almost_eq(_player.velocity.length(), Player.BASE_MOVE_SPEED / 4.0, 0.5, "a quarter of full speed after one frame")


func test_first_frame_after_release_already_decelerates() -> void:
	_player.move_input = Vector2(0, 1)
	_step(10)
	_player.move_input = Vector2.ZERO
	_step(1)
	assert_eq(_player.state_machine.current_name(), &"Idle")
	assert_almost_eq(_player.velocity.length(), Player.BASE_MOVE_SPEED * 0.75, 0.5, "lost a quarter of full speed in one frame")


func test_all_eight_inputs_move_in_their_iso_direction() -> void:
	var inputs: Array[Vector2] = [
		Vector2(0, -1), Vector2(1, -1), Vector2(1, 0), Vector2(1, 1),
		Vector2(0, 1), Vector2(-1, 1), Vector2(-1, 0), Vector2(-1, -1),
	]
	for input in inputs:
		_player.velocity = Vector2.ZERO
		_player.state_machine.change_to(&"Idle")
		_player.move_input = input
		_step(10)
		assert_almost_eq(_player.velocity.normalized(), Iso.input_to_world(input).normalized(), Vector2(0.001, 0.001), "input %s" % input)


func test_all_eight_inputs_give_equal_screen_speed() -> void:
	var inputs: Array[Vector2] = [
		Vector2(0, -1), Vector2(1, -1), Vector2(1, 0), Vector2(1, 1),
		Vector2(0, 1), Vector2(-1, 1), Vector2(-1, 0), Vector2(-1, -1),
	]
	for input in inputs:
		_player.velocity = Vector2.ZERO
		_player.state_machine.change_to(&"Idle")
		_player.move_input = input
		_step(10)
		assert_almost_eq(_player.velocity.length(), Player.BASE_MOVE_SPEED, 0.5, "input %s" % input)


func test_velocity_direction_follows_iso_input_to_world() -> void:
	_player.move_input = Vector2(1, 1)
	_step(10)
	assert_almost_eq(_player.velocity.normalized(), Iso.input_to_world(Vector2(1, 1)), Vector2(0.001, 0.001))


func test_idle_decelerates_to_zero_within_four_frames() -> void:
	_player.move_input = Vector2(0, 1)
	_step(10)
	_player.move_input = Vector2.ZERO
	_step(4)
	assert_eq(_player.velocity, Vector2.ZERO)
	assert_eq(_player.state_machine.current_name(), &"Idle")


func test_accel_and_friction_scale_with_move_speed() -> void:
	assert_almost_eq(_player.move_accel(), _player.move_speed() / Player.ACCEL_SECONDS, 0.001)
	assert_almost_eq(_player.move_friction(), _player.move_speed() / Player.STOP_SECONDS, 0.001)


func test_facing_follows_move_direction_and_animation_suffix() -> void:
	watch_signals(_player)
	_player.move_input = Vector2(1, -1)  # W+D: along the -y tile axis, screen up-right = ne
	_step(2)
	assert_eq(_player.facing_index, 5, "ne")
	assert_almost_eq(_player.facing, Vector2(32, -16).normalized(), Vector2(0.001, 0.001))
	assert_eq(_player.sprite.animation, &"walk_ne")
	assert_signal_emitted(_player, "facing_changed")


func test_facing_persists_into_idle() -> void:
	_player.move_input = Vector2(-1, 0)
	_step(2)
	_player.move_input = Vector2.ZERO
	_step(5)
	assert_eq(_player.facing_index, 2, "still faces w")
	assert_eq(_player.sprite.animation, &"idle_w")


func test_remote_player_ignores_local_input_gathering() -> void:
	# peer_id 0 is never the local peer, so _physics_process must not touch
	# move_input. This runs a real physics frame.
	_player.peer_id = 0
	_player.move_input = Vector2(0, 1)
	await wait_physics_frames(2)
	assert_eq(_player.move_input, Vector2(0, 1), "remote players keep replicated input")
