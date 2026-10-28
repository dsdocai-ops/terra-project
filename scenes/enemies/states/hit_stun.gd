extends EnemyState
## Flinching from a hit: only the knockback impulse moves the enemy, for
## `hit_stun_left` seconds, then back to Chase. Owned by combat-core (W2-A3).
## Sync: host-only; StateSync carries the position.
##
## The decisions — the decay maths and the stun clock — are the pure
## `EnemyStateLogic`; this state applies them to the Enemy.


func enter(_from: StringName) -> void:
	enemy.current_anim = &"hurt"
	enemy.telegraph_progress = -1.0
	enemy.hitbox.active = false


func physics_update(delta: float) -> void:
	enemy.decay_knockback(delta)
	enemy.velocity = enemy.knockback_velocity * machine.effective_scale
	enemy.move_and_slide()
	enemy.knockback_velocity = EnemyStateLogic.knockback_after_wall(enemy.knockback_velocity, enemy.is_on_wall())
	var tick := EnemyStateLogic.tick_down(enemy.hit_stun_left, delta)
	enemy.hit_stun_left = tick.left
	if tick.over:
		machine.change_to(&"Chase")
