extends EnemyState
## Closing on the target (or holding a firing distance), then Attack when the
## pattern's trigger range is met and the cooldown is up. Owned by enemies-ai.
## Sync: host-only.
##
## The decisions — retarget cadence, keep-distance bands, the attack gate —
## are the pure `EnemyStateLogic`; this state applies them to the Enemy.

var _retarget_left: float = 0.0


func enter(_from: StringName) -> void:
	enemy.current_anim = &"walk"
	_retarget_left = 0.0


func physics_update(delta: float) -> void:
	var tick := EnemyStateLogic.tick_down(_retarget_left, delta)
	if tick.over or not is_instance_valid(enemy.target):
		_retarget_left = EnemyStateLogic.RETARGET_SECONDS
		enemy.target = enemy.pick_target()
	else:
		_retarget_left = tick.left
	var target: Node2D = enemy.target
	if target == null:
		machine.change_to(&"Idle")
		return
	var to_target: Vector2 = target.global_position - enemy.global_position
	var dist: float = to_target.length()
	var pattern: AttackPattern = _choose_pattern()
	if pattern != null and EnemyStateLogic.chase_attack(dist, pattern.trigger_range, enemy.attack_cooldown_left):
		enemy.next_attack = pattern
		machine.change_to(&"Attack")
		return
	match EnemyStateLogic.chase_move(dist, enemy.data.keep_distance):
		EnemyStateLogic.ChaseMove.BACK_OFF:
			enemy.move_toward_point(enemy.global_position - to_target, enemy.move_speed(), delta)
		EnemyStateLogic.ChaseMove.HOLD:
			enemy.stop_moving(delta)
		EnemyStateLogic.ChaseMove.APPROACH:
			enemy.move_toward_point(target.global_position, enemy.move_speed(), delta)


func _choose_pattern() -> AttackPattern:
	if enemy.data.attacks.is_empty():
		return null
	return enemy.data.attacks[0]
