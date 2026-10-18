extends GutTest
## Tests for facing sectors (Iso.facing_index) and Move/Idle movement math.
## Owned by player-controller.

const PLAYER_SCENE := "res://scenes/player/player.tscn"
const DT := 1.0 / 60.0

## Screen-space unit vectors for the 8 facings, in Player.FACING_SUFFIXES
## order: s, sw, w, nw, n, ne, e, se. Diagonals follow the tile axes.
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


# Iso.facing_index

func test_exact_directions_map_to_their_index() -> void:
	for i in FACING_VECTORS.size():
		assert_eq(Iso.facing_index(FACING_VECTORS[i].normalized()), i, "facing %s" % Player.FACING_SUFFIXES[i])


func test_sector_boundaries_sit_midway_between_neighbours() -> void:
	# Between e (0 deg) and se (26.565 deg) the boundary is 13.28 deg.
	assert_eq(Iso.facing_index(Vector2.RIGHT.rotated(deg_to_rad(12.0))), 6, "just below boundary is e")
	assert_eq(Iso.facing_index(Vector2.RIGHT.rotated(deg_to_rad(15.0))), 7, "just above boundary is se")
	# Between se (26.565) and s (90) the boundary is 58.28 deg.
	assert_eq(Iso.facing_index(Vector2.RIGHT.rotated(deg_to_rad(57.0))), 7)
	assert_eq(Iso.facing_index(Vector2.RIGHT.rotated(deg_to_rad(60.0))), 0)


func test_hysteresis_keeps_current_sector_near_boundary() -> void:
	var near_boundary := Vector2.RIGHT.rotated(deg_to_rad(14.5))
	assert_eq(Iso.facing_index(near_boundary, 6, 3.0), 6, "stays e within hysteresis")
	assert_eq(Iso.facing_index(near_boundary, 7, 3.0), 7, "stays se within hysteresis")
	var well_past := Vector2.RIGHT.rotated(deg_to_rad(20.0))
	assert_eq(Iso.facing_index(well_past, 6, 3.0), 7, "switches once clearly past")


func test_zero_vector_keeps_current() -> void:
	assert_eq(Iso.facing_index(Vector2.ZERO, 3), 3)
	assert_eq(Iso.facing_index(Vector2.ZERO), 0)


# Movement

func test_move_reaches_base_speed_within_four_frames() -> void:
	_player.move_input = Vector2(1, 0)
	_step(5)
	assert_almost_eq(_player.velocity.length(), Player.BASE_MOVE_SPEED, 0.5)


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
	_step(5)
	assert_eq(_player.velocity, Vector2.ZERO)
	assert_eq(_player.state_machine.current_name(), &"Idle")


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
