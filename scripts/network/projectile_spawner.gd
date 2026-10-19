class_name ProjectileSpawner
extends MultiplayerSpawner
## Spawns projectiles under World/Entities on the host (SPEC-networking,
## W2-B3). combat-core's ProjectilePool drives this once it lands; until
## then the debug console and tests call spawn_projectile() directly.
## Sync: the host calls spawn_projectile(); MultiplayerSpawner replays the
## custom spawn function on every peer, including late joiners, and despawns
## when the host frees the node. Spawned roots stay host-owned; a client
## never spawns projectiles, it only renders the replicated pose.

const PLACEHOLDER_PROJECTILE: PackedScene = preload("res://scenes/network/placeholder_projectile.tscn")

## Dev A's Projectile base replaces this placeholder when W2-A6 lands; the
## placeholder is the stand-in until then (recorded in .goals/LOG.md:
## blocked on Dev A W2-A6).
@export var projectile_scene: PackedScene = PLACEHOLDER_PROJECTILE

var _next_id: int = 1


func _ready() -> void:
	spawn_function = _spawn_from_data


## Host-only spawn: only the server spawns projectiles. Split out so unit
## tests can drive the client side without a second instance.
func _can_spawn() -> bool:
	return multiplayer.is_server()


## Host only. Returns the spawned root, or null on a client / on failure.
func spawn_projectile(info: ProjectileSpawnInfo) -> Node:
	if not _can_spawn():
		push_warning("ProjectileSpawner.spawn_projectile refused: only the host spawns projectiles")
		return null
	return spawn(info.to_dict())


## Runs on every peer with the host's ProjectileSpawnInfo dictionary.
func _spawn_from_data(data: Variant) -> Node:
	var info := ProjectileSpawnInfo.from_dict(data as Dictionary)
	var projectile := projectile_scene.instantiate()
	projectile.name = "Projectile%d" % _next_id
	_next_id += 1
	projectile.position = info.spawn_position
	# The replicated pose and owner; Projectile (Dev A) must keep these names
	# so the swap-in stays mechanical (recorded in .goals/LOG.md).
	projectile.set("synced_position", info.spawn_position)
	projectile.set("synced_velocity", info.velocity)
	projectile.set("owner_peer_id", info.owner_peer_id)
	return projectile