extends EnemyState
## Standing until a player comes within aggro range, then Chase. Owned by
## enemies-ai. Sync: host-only.

const SCAN_SECONDS: float = 0.25

var _scan_left: float = 0.0


func enter(_from: StringName) -> void:
	enemy.current_anim = &"idle"
	enemy.telegraph_progress = -1.0


func physics_update(delta: float) -> void:
	enemy.stop_moving(delta)
	_scan_left -= delta
	if _scan_left > 0.0:
		return
	_scan_left = SCAN_SECONDS
	var target: Node2D = enemy.pick_target()
	if target != null and enemy.global_position.distance_to(target.global_position) <= enemy.data.aggro_range:
		enemy.target = target
		machine.change_to(&"Chase")
