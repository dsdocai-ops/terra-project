extends EnemyState
## Closing on the target (or holding a firing distance), then Attack when the
## pattern's trigger range is met and the cooldown is up. Owned by enemies-ai.
## Sync: host-only.

const RETARGET_SECONDS: float = 0.5

var _retarget_left: float = 0.0


func enter(_from: StringName) -> void:
	enemy.current_anim = &"walk"
	_retarget_left = 0.0


func physics_update(delta: float) -> void:
	_retarget_left -= delta
	if _retarget_left <= 0.0 or not is_instance_valid(enemy.target):
		_retarget_left = RETARGET_SECONDS
		enemy.target = enemy.pick_target()
	var target: Node2D = enemy.target
	if target == null:
		machine.change_to(&"Idle")
		return
	var to_target: Vector2 = target.global_position - enemy.global_position
	var dist: float = to_target.length()
	var pattern: AttackPattern = _choose_pattern()
	if pattern != null and dist <= pattern.trigger_range and enemy.attack_cooldown_left <= 0.0:
		enemy.next_attack = pattern
		machine.change_to(&"Attack")
		return
	var keep: float = enemy.data.keep_distance
	if keep > 0.0 and dist < keep * 0.8:
		enemy.move_toward_point(enemy.global_position - to_target, enemy.data.move_speed, delta)
	elif keep > 0.0 and dist <= keep:
		enemy.stop_moving(delta)
	else:
		enemy.move_toward_point(target.global_position, enemy.data.move_speed, delta)


func _choose_pattern() -> AttackPattern:
	if enemy.data.attacks.is_empty():
		return null
	return enemy.data.attacks[0]
