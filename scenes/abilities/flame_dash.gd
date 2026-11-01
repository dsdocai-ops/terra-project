class_name FlameDashCast
extends AbilityCast
## Flame Dash (SPEC-abilities section 8, Fire): the player dashes along the aim
## and leaves a fire wall where the dash began. The extra number is the dash
## distance in pixels. The dash is the existing knockback shove with no stun, so
## walls still stop it. Owned by abilities. Sync: host only, the player moves on
## the host.

const WALL_RADIUS: float = 40.0
const WALL_TICK_SECONDS: float = 0.5
## The fire wall hits at this share of the ability's damage.
const WALL_DAMAGE_FACTOR: float = 0.5
## The knockback decays linearly over this long, so its distance is half the
## impulse times the decay time.
const SHOVE_DECAY_SECONDS: float = Player.KNOCKBACK_DECAY_SECONDS


func _perform() -> void:
	var start: Vector2 = origin()
	spawn_zone(start, WALL_RADIUS * size_mult(), life_seconds, WALL_TICK_SECONDS, scaled_hit(WALL_DAMAGE_FACTOR))
	if player != null:
		var impulse: Vector2 = aim_dir * extra() / (SHOVE_DECAY_SECONDS * 0.5)
		player.apply_knockback(impulse, 0.0, HitInfo.new())
