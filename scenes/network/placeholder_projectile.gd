extends Node2D
## Temporary stand-in for Dev A's Projectile base + ProjectilePool (W2-A6):
## a straight-line projectile whose pose is host-authored and replicated, so
## projectile spawner reuse and client presentation work before real
## projectiles land. Not a real projectile — no pierce, bounce, homing, or
## hitbox.
## Owned by networking (W2-B3). Sync: the root is host-owned; StateSync
## replicates synced_position and synced_velocity from the host to every
## peer. The host integrates movement; clients present the replicated pose.

var synced_position: Vector2 = Vector2.ZERO
var synced_velocity: Vector2 = Vector2.ZERO
var owner_peer_id: int = 1
var alive_time: float = 0.0
var lifetime: float = 4.0


func _ready() -> void:
	synced_position = global_position


func _physics_process(delta: float) -> void:
	alive_time += delta
	if alive_time >= lifetime:
		queue_free()
		return
	if multiplayer.is_server():
		global_position += synced_velocity * delta
		synced_position = global_position  # host-authored; StateSync sends it
	else:
		global_position = synced_position  # present the replicated pose