class_name AffixShielded
extends EliteBehavior
## SHIELDED (SPEC-enemies-ai): a shield that absorbs SHIELD_MAX_HITS hits. A heavy
## hit breaks it outright and the heavy lands. Once broken it recharges after
## SHIELD_RECHARGE_SECONDS, so the shield is periodic. Owned by enemies-ai; host
## only, run from Enemy's host-side physics and damage path.

const SHIELD_MAX_HITS: int = 3
const SHIELD_RECHARGE_SECONDS: float = 5.0

var hits_left: int = SHIELD_MAX_HITS
var recharge_left: float = 0.0
var _up: bool = false


func on_spawn(_enemy: Enemy) -> void:
	_raise()


func process(delta: float, _enemy: Enemy) -> void:
	if _up:
		return
	recharge_left -= delta
	if recharge_left <= 0.0:
		_raise()


func absorbs(_enemy: Enemy, hit: HitInfo) -> bool:
	if not _up:
		return false
	if hit.is_heavy:
		_break()
		return false
	hits_left -= 1
	if hits_left <= 0:
		_break()
	return true


## Whether the shield is up now.
func is_up() -> bool:
	return _up


func _raise() -> void:
	_up = true
	hits_left = SHIELD_MAX_HITS
	recharge_left = 0.0


func _break() -> void:
	_up = false
	hits_left = 0
	recharge_left = SHIELD_RECHARGE_SECONDS
