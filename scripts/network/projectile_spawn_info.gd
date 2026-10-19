class_name ProjectileSpawnInfo
extends RefCounted
## What the host needs to spawn one projectile on every peer. Owned by
## networking (W2-B3). Filled by combat-core's ProjectilePool once the
## Projectile base lands (blocked on Dev A W2-A6); until then the debug
## console and tests build it directly against the host's spawner.
## Sync: serialized to a Dictionary of plain types (String, Vector2, int)
## for MultiplayerSpawner.spawn(), which sends it to every peer;
## from_dict() rebuilds it there.

const DEFAULT_PROJECTILE_ID: StringName = &"pebble"

var projectile_id: StringName = DEFAULT_PROJECTILE_ID
var spawn_position: Vector2 = Vector2.ZERO
var velocity: Vector2 = Vector2.ZERO
## Who fired it; host-only damage attribution in future kill bookkeeping.
var owner_peer_id: int = 1


func _init(
	p_projectile_id: StringName = DEFAULT_PROJECTILE_ID,
	p_spawn_position: Vector2 = Vector2.ZERO,
	p_velocity: Vector2 = Vector2.ZERO,
	p_owner_peer_id: int = 1,
) -> void:
	projectile_id = p_projectile_id
	spawn_position = p_spawn_position
	velocity = p_velocity
	owner_peer_id = p_owner_peer_id


func to_dict() -> Dictionary:
	return {
		"projectile_id": String(projectile_id),
		"spawn_position": spawn_position,
		"velocity": velocity,
		"owner_peer_id": owner_peer_id,
	}


static func from_dict(data: Dictionary) -> ProjectileSpawnInfo:
	var raw_position: Variant = data.get("spawn_position", Vector2.ZERO)
	var pos: Vector2 = raw_position if raw_position is Vector2 else Vector2.ZERO
	var raw_velocity: Variant = data.get("velocity", Vector2.ZERO)
	var vel: Vector2 = raw_velocity if raw_velocity is Vector2 else Vector2.ZERO
	return ProjectileSpawnInfo.new(
		StringName(str(data.get("projectile_id", String(DEFAULT_PROJECTILE_ID)))),
		pos,
		vel,
		int(data.get("owner_peer_id", 1)),
	)