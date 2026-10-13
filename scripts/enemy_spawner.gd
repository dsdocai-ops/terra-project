extends Node3D
## Places the test robots on the ground around the spawn when the level starts.
## Spawn points are (x, z) in metres; the height comes from a ray down onto the terrain.

const ENEMY := preload("res://scripts/enemy.gd")
const SPAWNS := [Vector2(14, -26), Vector2(-22, -18), Vector2(2, -42), Vector2(-30, -40)]


func _ready() -> void:
	var player := get_node("../Player") as Node3D
	# Wait one physics frame so the terrain collision exists before we ray down onto it.
	await get_tree().physics_frame
	for p in SPAWNS:
		var enemy := ENEMY.new()
		enemy.player = player
		enemy.position = Vector3(p.x, _ground_height(p), p.y)  # before add_child: _ready() saves it as the respawn spot
		add_child(enemy)


func _ground_height(p: Vector2) -> float:
	var from := Vector3(p.x, 200.0, p.y)
	var query := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 400.0)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	return hit["position"].y if not hit.is_empty() else 0.0
