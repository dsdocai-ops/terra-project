extends EnemyState
## Poise broke: the enemy is dazed for `EnemyData.stagger_seconds`. Entering
## cancels the current attack (the Attack state's exit clears the hitbox, and the
## telegraph is cleared here), the enemy takes +25% damage through a Hurtbox
## damage-taken factor, and on the way out poise refills to full. Knockback from
## the breaking hit slides it like HitStun. Owned by enemies-ai (combat v2 C2).
## Sync: host-only; the `staggered` flag it sets rides StateSync so clients can
## draw the dazed marker.
##
## The decisions — the clock length and the stun clock itself — are the pure
## `EnemyStateLogic` (`stagger_length`, `tick_down`); this state applies them
## to the Enemy.

const DAMAGE_SOURCE: StringName = &"stagger"

var _left: float = 0.0


func enter(_from: StringName) -> void:
	enemy.current_anim = &"hurt"
	enemy.telegraph_progress = -1.0
	enemy.hitbox.active = false
	enemy.staggered = true
	enemy.hurtbox.set_damage_taken_factor(DAMAGE_SOURCE, EnemyStateLogic.STAGGER_DAMAGE_TAKEN)
	_left = EnemyStateLogic.stagger_length(enemy.data != null, enemy.data.stagger_seconds if enemy.data != null else 0.0)


func exit(_to: StringName) -> void:
	enemy.staggered = false
	enemy.hurtbox.clear_damage_taken_factor(DAMAGE_SOURCE)
	enemy.refill_poise()


func physics_update(delta: float) -> void:
	enemy.decay_knockback(delta)
	enemy.velocity = enemy.knockback_velocity * machine.effective_scale
	enemy.move_and_slide()
	enemy.knockback_velocity = EnemyStateLogic.knockback_after_wall(enemy.knockback_velocity, enemy.is_on_wall())
	var tick := EnemyStateLogic.tick_down(_left, delta)
	_left = tick.left
	if tick.over:
		machine.change_to(&"Chase")
