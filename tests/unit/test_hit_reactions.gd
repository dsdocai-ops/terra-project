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


# --- flinch vs stun (combat v2 C5) --------------------------------------------------------

func _enemy_hit(heavy: bool) -> HitInfo:
	var hit := HitInfo.new()
	hit.base_damage = 4.0
	hit.knockback = Vector2(120, 0)
	hit.hit_stun_seconds = 0.2
	hit.is_heavy = heavy
	return hit


func test_a_light_hit_is_a_flinch_and_the_player_keeps_control() -> void:
	_player.apply_knockback(Vector2(120, 0), 0.2, _enemy_hit(false))
	assert_eq(_player.state_machine.current_name(), &"Idle", "no state change")
	assert_gt(_player.knockback_velocity.x, 0.0, "but the shove is there")
	_player.move_input = Vector2(0, 1)
	_player.state_machine.physics_update(FRAME)
	assert_eq(_player.state_machine.current_name(), &"Move", "input still works straight away")


func test_a_light_hit_still_pushes_the_player() -> void:
	_player.apply_knockback(Vector2(120, 0), 0.2, _enemy_hit(false))
	for _frame in 6:
		_player._shove_from_flinch(FRAME)
	assert_gt(_player.position.x, 0.0, "pushed along the hit")
	assert_almost_eq(_player.position.y, 0.0, 0.001)
	for _frame in 20:
		_player._shove_from_flinch(FRAME)
	assert_eq(_player.knockback_velocity, Vector2.ZERO, "the shove decays away")


func test_a_flinch_shove_is_blocked_by_a_wall() -> void:
	_add_wall(Vector2(28, 0))
	_player.apply_knockback(Vector2(400, 0), 0.2, _enemy_hit(false))
	for _frame in 30:
		_player._shove_from_flinch(FRAME)
	assert_lte(_player.position.x, 16.5, "stopped at the wall")
	assert_eq(_player.knockback_velocity, Vector2.ZERO)


func test_a_heavy_hit_is_the_full_hit_stun() -> void:
	_player.apply_knockback(Vector2(120, 0), 0.2, _enemy_hit(true))
	assert_eq(_player.state_machine.current_name(), &"HitStun")
	_player.move_input = Vector2(1, 0)
	_step(0.1)
	assert_eq(_player.state_machine.current_name(), &"HitStun", "no control while stunned")
	_step(0.2)
	assert_ne(_player.state_machine.current_name(), &"HitStun", "free after the stun")


func test_a_hit_arriving_through_the_hurtbox_is_a_flinch_when_light_and_a_stun_when_heavy() -> void:
	assert_true(_player.hurtbox.receive(_enemy_hit(false)))
	assert_eq(_player.state_machine.current_name(), &"Idle", "light: still in control")
	assert_true(_player.hurtbox.invulnerable, "the 0.4 s i-frames still apply")
	_player.advance_hit_iframes(0.5)
	assert_true(_player.hurtbox.receive(_enemy_hit(true)))
	assert_eq(_player.state_machine.current_name(), &"HitStun", "heavy: stunned")


func test_a_flinch_does_not_cut_a_charge_but_a_slam_does() -> void:
	var controller: AttackController = _player.get_node("AttackController") as AttackController
	controller.apply(AttackController.Kind.HEAVY_PRESS, Vector2.RIGHT, 0.0)
	assert_eq(_player.state_machine.current_name(), &"HeavyCharge")
	_player.apply_knockback(Vector2(60, 0), 0.2, _enemy_hit(false))
	assert_eq(_player.state_machine.current_name(), &"HeavyCharge", "chip damage does not break the charge")
	_player.apply_knockback(Vector2(60, 0), 0.2, _enemy_hit(true))
	assert_eq(_player.state_machine.current_name(), &"HitStun", "a slam does")


func test_enemy_attack_patterns_set_the_hit_weight_and_poise() -> void:
	var enemy: Enemy = (load("res://scenes/enemies/enemy.tscn") as PackedScene).instantiate() as Enemy
	enemy.setup(&"hollow_miner")
	add_child_autofree(enemy)
	var pattern: AttackPattern = (load("res://data/enemies/attacks/miner_swing.tres") as AttackPattern).duplicate() as AttackPattern
	enemy.next_attack = pattern
	enemy.machine.change_to(&"Attack")
	var light: HitInfo = enemy.machine.current.call(&"_build_hit") as HitInfo
	assert_false(light.is_heavy, "a normal swing is light")
	pattern.is_heavy = true
	pattern.poise_damage = 25.0
	var heavy: HitInfo = enemy.machine.current.call(&"_build_hit") as HitInfo
	assert_true(heavy.is_heavy, "a heavy pattern says so")
	assert_eq(heavy.poise_damage, 25.0)
