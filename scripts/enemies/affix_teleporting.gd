class_name AffixTeleporting
extends EliteBehavior
## TELEPORTING (SPEC-enemies-ai): every BLINK_SECONDS it telegraphs for
## TELEGRAPH_SECONDS, then blinks to BEHIND_DISTANCE past its target, on the side
## away from where it stood. The telegraph shows on the enemy's replicated
## telegraph progress. Owned by enemies-ai; host only.

const BLINK_SECONDS: float = 6.0
const TELEGRAPH_SECONDS: float = 0.6
const BEHIND_DISTANCE: float = 40.0

var _cooldown_left: float = BLINK_SECONDS
var _telegraph_left: float = -1.0


func process(delta: float, enemy: Enemy) -> void:
	if _telegraph_left >= 0.0:
		_telegraph_left -= delta
		enemy.telegraph_progress = 1.0 - clampf(_telegraph_left / TELEGRAPH_SECONDS, 0.0, 1.0)
		if _telegraph_left <= 0.0:
			_telegraph_left = -1.0
			enemy.telegraph_progress = -1.0
			_blink(enemy)
		return
	_cooldown_left -= delta
	if _cooldown_left <= 0.0 and enemy.target != null:
		_cooldown_left = BLINK_SECONDS
		_telegraph_left = TELEGRAPH_SECONDS


## Where a blink from `from` lands for a target at `target`: BEHIND_DISTANCE past
## the target, on the far side from `from`.
static func blink_point(from: Vector2, target: Vector2) -> Vector2:
	var away := target - from
	if away.is_zero_approx():
		return target + Vector2.RIGHT * BEHIND_DISTANCE
	return target + away.normalized() * BEHIND_DISTANCE


func _blink(enemy: Enemy) -> void:
	if enemy.target == null:
		return
	enemy.global_position = blink_point(enemy.global_position, enemy.target.global_position)
	enemy.synced_position = enemy.global_position
