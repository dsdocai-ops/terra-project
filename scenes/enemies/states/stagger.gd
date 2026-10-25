extends EnemyState
## Poise broke: the enemy is dazed for `EnemyData.stagger_seconds`. Entering
## cancels the current attack (the Attack state's exit clears the hitbox, and the
## telegraph is cleared here), the enemy takes +25% damage through a Hurtbox
## damage-taken factor, and on the way out poise refills to full. Knockback from
## the breaking hit slides it like HitStun. Owned by enemies-ai (combat v2 C2).
## Sync: host-only; the `staggered` flag it sets rides StateSync so clients can
## draw the dazed marker.

const DAMAGE_TAKEN_FACTOR: float = 1.25
const DAMAGE_SOURCE: StringName = &"stagger"
const DEFAULT_SECONDS: float = 0.8

var _left: float = 0.0


func enter(_from: StringName) -> void:
	enemy.current_anim = &"hurt"
	enemy.telegraph_progress = -1.0
	enemy.hitbox.active = false
	enemy.staggered = true
	enemy.hurtbox.set_damage_taken_factor(DAMAGE_SOURCE, DAMAGE_TAKEN_FACTOR)
	_left = enemy.data.stagger_seconds if enemy.data != null else DEFAULT_SECONDS


func exit(_to: StringName) -> void:
	enemy.staggered = false
	enemy.hurtbox.clear_damage_taken_factor(DAMAGE_SOURCE)
	enemy.refill_poise()


func physics_update(delta: float) -> void:
	enemy.decay_knockback(delta)
	enemy.velocity = enemy.knockback_velocity * machine.effective_scale
	enemy.move_and_slide()
	if enemy.is_on_wall():
		enemy.knockback_velocity = Vector2.ZERO
	_left -= delta
	if _left <= 0.0:
		machine.change_to(&"Chase")
