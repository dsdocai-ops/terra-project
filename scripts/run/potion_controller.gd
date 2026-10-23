class_name PotionController
extends Node
## One player's potion belt (SPEC-run-economy "Potions"): slots from the Alchemist
## level (1/2/3), the types the Alchemist unlocked, starting potions, and the
## `potion` action (E). Owned by run-economy (W5-B3).
##
## Sync: host-authoritative. The held potions live in the player's
## `RunPlayerState.potions` (host-written, sent to the owning peer). `use()` is the
## host body; a client's use forwards up as `interaction_forwarded`, the same
## stop-at-the-signal shape as Chest (SPEC-run-economy names `request_use_potion`,
## and the RPC is networking's to add).
##
## Effects go through the player's own nodes by name, so nothing here needs Dev A's
## Health to exist: heal prefers `Health.heal(int)` and falls back to the
## StatBlock's `current_hp_ratio`; haste is a StatBlock modifier removed after its
## duration; cleanse clears StatusEffects; shield is a hit counter the damage path
## consumes through `absorb_hit()` (blocked on Dev A: Health calls it).

signal potion_used(peer_id: int, potion_id: StringName)
signal interaction_forwarded(peer_id: int)

const DATA_DIR: String = "res://data/potions/"
const MAX_SLOTS: int = 3
## Potion Mastery (Delver tree): heals +15% of max HP per rank.
const POTION_MASTERY: StringName = &"potion_mastery"
const MASTERY_HEAL_PER_RANK: float = 0.15
const HASTE_SOURCE: StringName = &"potion_haste"
const STATUS_NODE: NodePath = ^"StatusEffects"

var player: Player = null
## Slots this belt has (Alchemist level), 0 to MAX_SLOTS.
var slots: int = 0
## Potion Mastery rank for the heal bonus; the host sets it from the profile.
var mastery_rank: int = 0
## Hits the shield potion will still absorb.
var shield_hits: int = 0

var _haste_serial: int = 0


# --- pure rules -------------------------------------------------------------


static func slots_for_alchemist_level(level: int) -> int:
	return clampi(level, 0, MAX_SLOTS)


static func data_for(id: StringName) -> PotionData:
	var path: String = DATA_DIR + String(id) + ".tres"
	if id == &"" or not ResourceLoader.exists(path):
		return null
	return load(path) as PotionData


## The starting belt from a profile's `potions` dict: the starting ids the
## Alchemist unlocked, in order, capped at the slot count.
static func starting_potions(profile_potions: Dictionary) -> Array[StringName]:
	var belt: Array[StringName] = []
	var slot_count: int = int(profile_potions.get(PlayerProfile.POTION_SLOTS, 0))
	var unlocked: Array = profile_potions.get(PlayerProfile.POTION_TYPES, [])
	var starting: Array = profile_potions.get(PlayerProfile.POTION_STARTING, [])
	for raw: Variant in starting:
		var id: StringName = StringName(str(raw))
		if belt.size() < slot_count and unlocked.has(String(id)) and data_for(id) != null:
			belt.append(id)
	return belt


## Heal amount for `max_hp`: 35% plus 15% per Potion Mastery rank.
static func heal_amount(max_hp: float, heal_fraction: float, rank: int, multiplier: float = 1.0) -> int:
	return roundi(max_hp * total_heal_fraction(heal_fraction, rank, multiplier))


## The share of max HP a heal restores: the base plus Potion Mastery, times any
## healing multiplier from status effects.
static func total_heal_fraction(heal_fraction: float, rank: int, multiplier: float = 1.0) -> float:
	return (heal_fraction + MASTERY_HEAL_PER_RANK * maxi(rank, 0)) * multiplier


static func has_room(belt: Array[StringName], slot_count: int) -> bool:
	return belt.size() < slot_count


## Adds `id` to a belt when a slot is free; false (belt unchanged) when full or unknown.
static func add_to_belt(belt: Array[StringName], slot_count: int, id: StringName) -> bool:
	if not has_room(belt, slot_count) or data_for(id) == null:
		return false
	belt.append(id)
	return true


## Rest rooms and shops refill the belt to the starting loadout.
static func refill(belt: Array[StringName], slot_count: int, starting: Array[StringName]) -> void:
	belt.clear()
	for id: StringName in starting:
		if belt.size() < slot_count:
			belt.append(id)


# --- the action -------------------------------------------------------------


func _slice() -> RunPlayerState:
	if player == null or GameState.run == null:
		return null
	return GameState.run.get_player(player.peer_id)


func belt() -> Array[StringName]:
	var slice: RunPlayerState = _slice()
	return slice.potions if slice != null else ([] as Array[StringName])


## The `potion` action. The host drinks the first potion on the belt; a client
## forwards. Returns the potion id used, or &"" when nothing was drunk.
func use() -> StringName:
	if player == null:
		return &""
	if not NetworkManager.is_host:
		if NetworkManager.is_active:
			interaction_forwarded.emit(player.peer_id)
		return &""
	var slice: RunPlayerState = _slice()
	if slice == null or slice.potions.is_empty() or not slice.is_standing():
		return &""
	var id: StringName = slice.potions[0]
	var data: PotionData = data_for(id)
	if data == null:
		slice.potions.remove_at(0)
		return &""
	slice.potions.remove_at(0)
	_apply(data)
	potion_used.emit(player.peer_id, id)
	return id


func _apply(data: PotionData) -> void:
	match data.kind:
		PotionData.Kind.HEAL:
			_heal(data.heal_fraction)
		PotionData.Kind.CLEANSE:
			var status: StatusEffects = player.get_node_or_null(STATUS_NODE) as StatusEffects
			if status != null:
				status.clear_all()
		PotionData.Kind.HASTE:
			_haste(data)
		PotionData.Kind.SHIELD:
			shield_hits += data.absorb_hits


func _heal(fraction: float) -> void:
	var block: StatBlock = player.get_node_or_null(StatusEffects.STAT_BLOCK_NODE) as StatBlock
	if block == null:
		return
	var multiplier: float = 1.0
	var status: StatusEffects = player.get_node_or_null(STATUS_NODE) as StatusEffects
	if status != null:
		multiplier = status.healing_multiplier()
	var health: Node = player.get_node_or_null(StatusEffects.HEALTH_NODE)
	if health != null and health.has_method(&"heal"):
		health.call(&"heal", heal_amount(block.get_value(StatBlock.Stat.MAX_HP), fraction, mastery_rank, multiplier))
	else:
		block.current_hp_ratio = minf(1.0, block.current_hp_ratio + total_heal_fraction(fraction, mastery_rank, multiplier))


func _haste(data: PotionData) -> void:
	var block: StatBlock = player.get_node_or_null(StatusEffects.STAT_BLOCK_NODE) as StatBlock
	if block == null:
		return
	block.remove_source(HASTE_SOURCE)
	block.add_modifier(StatBlock.Stat.MOVE_SPEED, 0.0, data.speed_bonus, HASTE_SOURCE)
	_haste_serial += 1
	if is_inside_tree():
		get_tree().create_timer(data.duration).timeout.connect(_end_haste.bind(block, _haste_serial))


## Ends the haste only when no later potion has renewed it since this timer began.
func _end_haste(block: StatBlock, serial: int) -> void:
	if serial == _haste_serial and is_instance_valid(block):
		block.remove_source(HASTE_SOURCE)


## Consumed by the damage path: true when the shield swallowed this hit.
func absorb_hit() -> bool:
	if shield_hits <= 0:
		return false
	shield_hits -= 1
	return true
