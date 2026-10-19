class_name EnemySpawner
extends MultiplayerSpawner
## Spawns enemies under World/Entities on the host (SPEC-networking,
## W2-B3). enemies-ai's SpawnDirector drives this once it lands; until then
## the debug console and tests call spawn_enemy() directly.
## Sync: the host calls spawn_enemy(); MultiplayerSpawner replays the custom
## spawn function on every peer, including late joiners, and despawns when
## the host frees the node. Spawned roots and their StateSync stay
## host-owned; a client never spawns or resolves hits, it only renders what
## the host replicated.

const PLACEHOLDER_ENEMY: PackedScene = preload("res://scenes/network/placeholder_enemy.tscn")

## Dev A's scenes/enemies/enemy_base.tscn replaces this placeholder when
## W2-A9 lands; the placeholder is the stand-in until then (recorded in
## .goals/LOG.md: blocked on Dev A W2-A9).
@export var enemy_scene: PackedScene = PLACEHOLDER_ENEMY

var _next_fight_id: int = 1


func _ready() -> void:
	spawn_function = _spawn_from_data


## Host-only spawn: only the server spawns enemies. Split out so unit tests
## can drive the client side without a second instance.
func _can_spawn() -> bool:
	return multiplayer.is_server()


## Host only. Returns the spawned root, or null on a client / on failure.
## A fight_id of 0 gets one assigned so every spawned enemy names itself.
func spawn_enemy(info: EnemySpawnInfo) -> Node:
	if not _can_spawn():
		push_warning("EnemySpawner.spawn_enemy refused: only the host spawns enemies")
		return null
	if info.fight_id == 0:
		info.fight_id = _next_fight_id
		_next_fight_id += 1
	return spawn(info.to_dict())


## Runs on every peer with the host's EnemySpawnInfo dictionary.
func _spawn_from_data(data: Variant) -> Node:
	var info := EnemySpawnInfo.from_dict(data as Dictionary)
	var enemy := enemy_scene.instantiate()
	enemy.name = "Enemy%d" % info.fight_id
	enemy.position = info.spawn_position
	# The replicated pose and per-fight id; enemy_base (Dev A) must keep these
	# names so the swap-in stays mechanical (recorded in .goals/LOG.md).
	enemy.set("synced_position", info.spawn_position)
	enemy.set("fight_id", info.fight_id)
	if info.elite:
		enemy.set("elite", true)
	return enemy