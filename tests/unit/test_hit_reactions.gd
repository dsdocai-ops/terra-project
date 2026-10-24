extends GutTest
## Tests for the player's hit reactions (SPEC-combat-core, "Hit reactions"):
## HitStun state, knockback impulse with wall block, 0.4 s post-hit i-frames.
## Owned by combat-core. Steps the state machine by hand so the physics
## server never runs between asserts.

const PLAYER_SCENE := "res://scenes/player/player.tscn"
const FRAME := 1.0 / 60.0

var _player: Player


func before_each() -> void:
	_player = (load(PLAYER_SCENE) as PackedScene).instantiate() as Player
	add_child_autofree(_player)
	_player.position = Vector2.ZERO


func _step(seconds: float) -> void:
	var remaining := seconds
	while remaining > 0.0:
		var dt := minf(FRAME, remaining)
		_player.state_machine.physics_update(dt)
		remaining -= dt


func _add_wall(center: Vector2) -> void:
	var wall := StaticBody2D.new()
	var shape := CollisionShape2D.new()
	shape.shape = RectangleShape2D.new()
	(shape.shape as RectangleShape2D).size = Vector2(8, 64)
	wall.add_child(shape)
	wall.position = center
	add_child_autofree(wall)


# --- HitStun ----------------------------------------------------------------

func test_knockback_enters_hit_stun() -> void:
	_player.apply_knockback(Vector2(60, 0), 0.15)
	assert_eq(_player.state_machine.current_name(), &"HitStun")


func test_hit_stun_lasts_its_seconds_then_returns_to_idle() -> void:
	_player.apply_knockback(Vector2.ZERO, 0.15)
	_step(0.1)
	assert_eq(_player.state_machine.current_name(), &"HitStun", "still stunned at 0.1 s")
	_step(0.1)
	assert_eq(_player.state_machine.current_name(), &"Idle", "free again after 0.15 s")


func test_hit_stun_returns_to_move_when_input_is_held() -> void:
	_player.apply_knockback(Vector2.ZERO, 0.1)
	_player.move_input = Vector2(1, 0)
	_step(0.2)
	assert_eq(_player.state_machine.current_name(), &"Move")


func test_hit_stun_ignores_move_input() -> void:
	_player.apply_knockback(Vector2.ZERO, 0.3)
	_player.move_input = Vector2(1, 0)
	_step(0.1)
	assert_eq(_player.state_machine.current_name(), &"HitStun")
	assert_almost_eq(_player.position.x, 0.0, 0.001, "no walking while stunned")


func test_a_second_hit_extends_the_stun_rather_than_stacking_states() -> void:
	_player.apply_knockback(Vector2.ZERO, 0.1)
	_step(0.05)
	_player.apply_knockback(Vector2.ZERO, 0.3)
	_step(0.2)
	assert_eq(_player.state_machine.current_name(), &"HitStun")


# --- knockback --------------------------------------------------------------

func test_knockback_pushes_along_the_impulse() -> void:
	_player.apply_knockback(Vector2(120, 0), 0.5)
	_step(0.1)
	assert_gt(_player.position.x, 0.0, "pushed in +x")
	assert_almost_eq(_player.position.y, 0.0, 0.001, "no drift off the impulse")


func test_knockback_decays_to_zero_over_point_two_seconds() -> void:
	_player.apply_knockback(Vector2(120, 0), 0.5)
	_step(0.1)
	assert_gt(_player.knockback_velocity.x, 0.0, "still moving at half the decay")
	assert_lt(_player.knockback_velocity.x, 120.0, "already slowing")
	_step(0.11)
	assert_almost_eq(_player.knockback_velocity.x, 0.0, 0.001, "gone by 0.2 s")


func test_wall_blocks_knockback() -> void:
	# Wall face at x = 24, player body radius 8: the body cannot pass x = 16.
	_add_wall(Vector2(28, 0))
	_player.apply_knockback(Vector2(400, 0), 0.5)
	_step(0.5)
	assert_lte(_player.position.x, 16.5, "stopped at the wall")
	assert_almost_eq(_player.knockback_velocity.x, 0.0, 0.001, "impulse dies on contact")


# --- post-hit i-frames ------------------------------------------------------

func test_start_hit_iframes_makes_the_hurtbox_invulnerable() -> void:
	_player.start_hit_iframes()
	assert_true(_player.hurtbox.invulnerable)


func test_iframes_last_point_four_seconds() -> void:
	_player.start_hit_iframes()
	_player.advance_hit_iframes(0.39)
	assert_true(_player.hurtbox.invulnerable, "still invulnerable at 0.39 s")
	_player.advance_hit_iframes(0.02)
	assert_false(_player.hurtbox.invulnerable, "hittable again after 0.4 s")


func test_damage_starts_iframes() -> void:
	_player.health.emit_signal("damaged", HitInfo.new())
	assert_true(_player.hurtbox.invulnerable, "any damage grants post-hit i-frames")
