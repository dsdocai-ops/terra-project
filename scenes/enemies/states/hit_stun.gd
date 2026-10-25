extends EnemyState
## Flinching from a hit: only the knockback impulse moves the enemy, for
## `hit_stun_left` seconds, then back to Chase. Owned by combat-core (W2-A3).
## Sync: host-only; StateSync carries the position.


func enter(_from: StringName) -> void:
	enemy.current_anim = &"hurt"
	enemy.telegraph_progress = -1.0
	enemy.hitbox.active = false


func physics_update(delta: float) -> void:
	enemy.decay_knockback(delta)
	enemy.velocity = enemy.knockback_velocity * machine.effective_scale
	enemy.move_and_slide()
	if enemy.is_on_wall():
		enemy.knockback_velocity = Vector2.ZERO
	enemy.hit_stun_left -= delta
	if enemy.hit_stun_left <= 0.0:
		machine.change_to(&"Chase")
