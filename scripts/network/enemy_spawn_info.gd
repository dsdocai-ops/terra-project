class_name EnemySpawnInfo
extends RefCounted
## What the host needs to spawn one enemy on every peer. Owned by networking
## (W2-B3). Filled by enemies-ai's SpawnDirector once EnemyData lands
## (blocked on Dev A W2-A9); until then the debug console and tests build it
## directly against the host's spawner.
## Sync: serialized to a Dictionary of plain types (String, Vector2, bool,
## int) for MultiplayerSpawner.spawn(), which sends it to every peer;
## from_dict() rebuilds it there.

const DEFAULT_KIND: StringName = &"grub"

var kind: StringName = DEFAULT_KIND
var spawn_position: Vector2 = Vector2.ZERO
var elite: bool = false
## Stable per-fight id, host-assigned, so kill/loot bookkeeping and despawns
## can name the enemy without relying on node paths.
var fight_id: int = 0


func _init(
	p_kind: StringName = DEFAULT_KIND,
	p_spawn_position: Vector2 = Vector2.ZERO,
	p_elite: bool = false,
	p_fight_id: int = 0,
) -> void:
	kind = p_kind
	spawn_position = p_spawn_position
	elite = p_elite
	fight_id = p_fight_id


func to_dict() -> Dictionary:
	return {
		"kind": String(kind),
		"spawn_position": spawn_position,
		"elite": elite,
		"fight_id": fight_id,
	}


static func from_dict(data: Dictionary) -> EnemySpawnInfo:
	var raw_position: Variant = data.get("spawn_position", Vector2.ZERO)
	var pos: Vector2 = raw_position if raw_position is Vector2 else Vector2.ZERO
	return EnemySpawnInfo.new(
		StringName(str(data.get("kind", String(DEFAULT_KIND)))),
		pos,
		bool(data.get("elite", false)),
		int(data.get("fight_id", 0)),
	)