class_name PlayerSpawnInfo
extends RefCounted
## What the host needs to spawn one player on every peer. Owned by networking.
## Sync: serialized to a Dictionary of plain types (int, String,
## PackedStringArray, Vector2) for MultiplayerSpawner.spawn(), which sends it
## to every peer; from_dict() rebuilds it there.

const DEFAULT_CHARACTER: StringName = &"wren"
const DEFAULT_CLASS: StringName = &"warrior"
const DEFAULT_WEAPONS: Array[StringName] = [&"pickaxe", &"crossbow"]

var peer_id: int = 0
var character_id: StringName = DEFAULT_CHARACTER
var class_id: StringName = DEFAULT_CLASS
var weapon_ids: Array[StringName] = []
var spawn_position: Vector2 = Vector2.ZERO
## Co-op slot (P1 to P4), chosen by the host; decides the player's color.
var slot: int = 0


func _init(
	p_peer_id: int = 0,
	p_character_id: StringName = DEFAULT_CHARACTER,
	p_class_id: StringName = DEFAULT_CLASS,
	p_weapon_ids: Array[StringName] = [],
	p_spawn_position: Vector2 = Vector2.ZERO,
	p_slot: int = 0,
) -> void:
	peer_id = p_peer_id
	character_id = p_character_id
	class_id = p_class_id
	weapon_ids = p_weapon_ids.duplicate() if not p_weapon_ids.is_empty() else DEFAULT_WEAPONS.duplicate()
	spawn_position = p_spawn_position
	slot = p_slot


func to_dict() -> Dictionary:
	var weapons := PackedStringArray()
	for id: StringName in weapon_ids:
		weapons.append(String(id))
	return {
		"peer_id": peer_id,
		"character_id": String(character_id),
		"class_id": String(class_id),
		"weapon_ids": weapons,
		"spawn_position": spawn_position,
		"slot": slot,
	}


static func from_dict(data: Dictionary) -> PlayerSpawnInfo:
	var weapons: Array[StringName] = []
	var raw_weapons: Variant = data.get("weapon_ids", PackedStringArray())
	if raw_weapons is PackedStringArray:
		for id: String in raw_weapons as PackedStringArray:
			weapons.append(StringName(id))
	var raw_position: Variant = data.get("spawn_position", Vector2.ZERO)
	var pos: Vector2 = raw_position if raw_position is Vector2 else Vector2.ZERO
	return PlayerSpawnInfo.new(
		int(data.get("peer_id", 0)),
		StringName(str(data.get("character_id", String(DEFAULT_CHARACTER)))),
		StringName(str(data.get("class_id", String(DEFAULT_CLASS)))),
		weapons,
		pos,
		int(data.get("slot", 0)),
	)
