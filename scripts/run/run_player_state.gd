class_name RunPlayerState
extends RefCounted
## One player's slice of a run: identity, loadout, earnings and the downed
## flag. Owned by run-economy (week 3); HUD and classes-characters read it.
## Sync: host-authoritative. The host writes this slice and sends it to the
## owning peer (peer_id); clients never mutate it.

## Peer that owns this slice (1 to 4 in co-op, 0/1 in solo).
var peer_id: int = 0
var character_id: StringName = &""
var class_id: StringName = &""
var weapon_ids: Array[StringName] = []
## Weapon id -> the mutation ids attached to that weapon.
var weapon_mutations: Dictionary[StringName, Array] = {}
var relics: Array[StringName] = []
var abilities: Array[StringName] = []
## Chosen Ascension id; empty until the first biome boss (week 3+).
var ascension: StringName = &""
var potions: Array[StringName] = []
var echo_shards_earned: int = 0
var class_xp_earned: int = 0
## This player's share of the party's shared gold.
var gold_share: int = 0
var is_downed: bool = false


func _init(
	p_peer_id: int = 0,
	p_character_id: StringName = &"",
	p_class_id: StringName = &"",
) -> void:
	peer_id = p_peer_id
	character_id = p_character_id
	class_id = p_class_id


## Adds a weapon to the loadout (idempotent) and records its mutations.
func add_weapon(weapon_id: StringName, mutations: Array[StringName] = []) -> void:
	if not weapon_ids.has(weapon_id):
		weapon_ids.append(weapon_id)
	weapon_mutations[weapon_id] = mutations.duplicate()


## The mutation ids attached to one weapon; empty when none are recorded.
func mutations_for(weapon_id: StringName) -> Array[StringName]:
	var result: Array[StringName] = []
	var raw: Variant = weapon_mutations.get(weapon_id)
	if raw is Array:
		for id: Variant in raw as Array:
			result.append(StringName(str(id)))
	return result
