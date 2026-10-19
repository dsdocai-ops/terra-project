class_name ScaledMover
extends Node2D
## Test double for time-manager: a node that registers a time group and steps
## its own x position by TimeManager.scale_for(self) each physics frame, so
## tests can observe how a slow, stop, or per-entity override affects scaled
## movement. Owned by time-manager. Sync: test-only, never in a game scene.

var group: int = TimeManager.Group.ENEMY
var speed: float = 100.0
var walked: float = 0.0


func _ready() -> void:
	TimeManager.set_group(self, group)


func _physics_process(delta: float) -> void:
	var step := speed * delta * TimeManager.scale_for(self)
	global_position.x += step
	walked += step
