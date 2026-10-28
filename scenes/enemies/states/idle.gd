extends EnemyState
## Standing until a player comes within aggro range, then Chase. Owned by
## enemies-ai. Sync: host-only.
##
## The decisions — scan cadence, aggro check, the target itself — are the pure
## `EnemyStateLogic` and `Targeting`; this state applies them to the Enemy.

var _scan_left: float = 0.0


func enter(_from: StringName) -> void:
	enemy.current_anim = &"idle"
	enemy.telegraph_progress = -1.0


func physics_update(delta: float) -> void:
	enemy.stop_moving(delta)
	var tick := EnemyStateLogic.tick_down(_scan_left, delta)
	if not tick.over:
		_scan_left = tick.left
		return
	_scan_left = EnemyStateLogic.SCAN_SECONDS
	var target: Node2D = enemy.pick_target()
	if target != null and EnemyStateLogic.in_aggro(enemy.global_position.distance_to(target.global_position), enemy.data.aggro_range):
		enemy.target = target
		machine.change_to(&"Chase")
