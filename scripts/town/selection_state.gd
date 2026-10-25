class_name SelectionState
extends RefCounted
## One player's pre-run choices (SPEC-town "Pre-run flow", W5-B5): character,
## class, two starting weapons and ready. Owned by town.
## Sync: each client sets its own and submits it to the host's RunSetup; the host
## validates and never trusts a client's claim about what it has unlocked beyond
## what it can check (see RunSetup).

const WEAPON_COUNT: int = 2

const REFUSAL_NONE: StringName = &""
const REFUSAL_CHARACTER_LOCKED: StringName = &"character_locked"
const REFUSAL_CLASS_LOCKED: StringName = &"class_locked"
const REFUSAL_WEAPON_COUNT: StringName = &"weapon_count"
const REFUSAL_WEAPON_DUPLICATE: StringName = &"weapon_duplicate"
const REFUSAL_WEAPON_LOCKED: StringName = &"weapon_locked"

var peer_id: int = 0
var character_id: StringName = PlayerSpawnInfo.DEFAULT_CHARACTER
var class_id: StringName = PlayerSpawnInfo.DEFAULT_CLASS
var weapon_ids: Array[StringName] = []
var ready: bool = false


func _init(p_peer_id: int = 0) -> void:
	peer_id = p_peer_id
	weapon_ids = [&"pickaxe", &"crossbow"]


func copy() -> SelectionState:
	var other: SelectionState = SelectionState.new(peer_id)
	other.character_id = character_id
	other.class_id = class_id
	other.weapon_ids = weapon_ids.duplicate()
	other.ready = ready
	return other


## Shape rules that need no profile: two distinct weapons.
func shape_refusal() -> StringName:
	if weapon_ids.size() != WEAPON_COUNT:
		return REFUSAL_WEAPON_COUNT
	if weapon_ids[0] == weapon_ids[1]:
		return REFUSAL_WEAPON_DUPLICATE
	return REFUSAL_NONE


## Shape rules plus what `profile` has unlocked. Pickaxe is unlocked from the
## start, so every class can always take it.
func refusal_for(profile: PlayerProfile) -> StringName:
	var shape: StringName = shape_refusal()
	if shape != REFUSAL_NONE:
		return shape
	if not profile.characters_unlocked.has(String(character_id)):
		return REFUSAL_CHARACTER_LOCKED
	var entry: Variant = profile.classes.get(String(class_id))
	if not entry is Dictionary or not bool((entry as Dictionary).get("unlocked", false)):
		return REFUSAL_CLASS_LOCKED
	for weapon_id: StringName in weapon_ids:
		if not profile.weapons_unlocked.has(String(weapon_id)):
			return REFUSAL_WEAPON_LOCKED
	return REFUSAL_NONE
