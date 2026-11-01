class_name BlackHoleCast
extends AbilityCast
## Black Hole (SPEC-abilities section 8, Void; SINKHOLE_SPEC "pull every enemy to a
## point, then implode"). Until the last IMPLODE_LEAD seconds of the cast, every
## enemy inside the radius is pulled toward the cursor on each step, through its own
## apply_knockback (the flinch hook, so its knockback_resist applies). Then the pull
## stops and one implode Zone spawns at the cursor: a single tick of the ability's
## hit to every enemy in the radius, on the step after the pull ends. Owned by
## abilities. Sync: host only; enemies move and the implode hits on the host.

const RADIUS: float = 72.0
## Pull speed in pixels per second: the impulse each enemy is given every step.
const PULL_SPEED: float = 240.0
## The last seconds of the cast, with no pull. The implode fires as they start.
const IMPLODE_LEAD: float = 0.2
## The implode's own life, half the lead, so its one tick lands before the cast ends.
const IMPLODE_SECONDS: float = IMPLODE_LEAD * 0.5
const KNOCKBACK_METHOD: StringName = &"apply_knockback"

## Seconds of scaled time left in the pull phase.
var _pull_left: float = 0.0
var _imploded: bool = false


func _perform() -> void:
	_pull_left = maxf(life_seconds - IMPLODE_LEAD, 0.0)


func advance(delta: float) -> void:
	if multiplayer.is_server() and not _imploded:
		var scaled: float = delta * TimeManager.scale_for(_timed_node())
		if _pull_left > scaled:
			_pull_left -= scaled
			_pull()
		else:
			_imploded = true
			_implode()
	super.advance(delta)


## Host: every enemy inside the radius gets one pull impulse toward the cursor. An
## enemy standing on the cursor has no direction, so it is skipped.
func _pull() -> void:
	var radius: float = RADIUS * size_mult()
	for node: Node in get_tree().get_nodes_in_group(Enemy.GROUP):
		var enemy := node as Node2D
		if enemy == null or not enemy.is_inside_tree():
			continue
		var offset: Vector2 = aim_point - enemy.global_position
		if offset.length() > radius or offset.is_zero_approx():
			continue
		if enemy.has_method(KNOCKBACK_METHOD):
			enemy.call(KNOCKBACK_METHOD, offset.normalized() * PULL_SPEED, 0.0)


## Host: the implode, one tick of the ability's hit on everything in the radius.
func _implode() -> void:
	spawn_zone(aim_point, RADIUS * size_mult(), IMPLODE_SECONDS, IMPLODE_SECONDS, build_hit())
