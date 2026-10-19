class_name HudModel
extends RefCounted
## Adapter that turns replicated player state into the typed properties the
## HUD widgets bind to: local HP ratio, teammate bars, weapon slots, and the
## floor label (SPEC-ui-hud data flow). Owned by ui-hud (Dev B).
## Sync: pure presentation. Reads whatever the bound callback returns
## (in the game that is NetworkManager.players, whose HP comes from each
## player's Health component through StateSync); never queries gameplay nodes
## by path, never sends. Host and client run the same code.

signal changed()

## Fallback when a player's Health component has not landed (Dev A W2-A1):
## show a full bar rather than nothing.
const DEFAULT_MAX_HP: int = 100
## Two starting weapon slots (weapons: W2-A7).
const WEAPON_SLOT_COUNT: int = 2

class HudTeammate:
	var peer_id: int = 0
	var display_name: String = ""
	var hp_ratio: float = 1.0
	var is_downed: bool = false
	var slot: int = 0


class HudWeaponSlot:
	var slot_index: int = 0
	var display_name: String = "-"
	var active: bool = false
	var cooldown_fraction: float = 0.0


var local_hp_ratio: float = 1.0
var local_is_downed: bool = false
var local_slot: int = 0
var teammates: Array[HudTeammate] = []
var weapon_slots: Array[HudWeaponSlot] = []
## Placeholder until run-economy's floor state arrives; GameState.floor_changed
## feeds it through the HUD.
var floor_label: String = "FLOOR -"

## Returns peer_id -> Player for the current session. Bound by the HUD to
## NetworkManager.players; unit tests bind a fake registry.
var _get_players: Callable = Callable()


func _init() -> void:
	for index: int in WEAPON_SLOT_COUNT:
		var slot := HudWeaponSlot.new()
		slot.slot_index = index
		weapon_slots.append(slot)


func bind(get_players: Callable) -> void:
	_get_players = get_players


## Recomputes local HP and the teammate list from the bound player registry,
## then announces the change. `local_peer_id` identifies the local player in
## the registry (NetworkManager.local_peer_id in the game).
func refresh(local_peer_id: int) -> void:
	teammates.clear()
	var source: Dictionary[int, Player] = {}
	if _get_players.is_valid():
		source = _get_players.call() as Dictionary[int, Player]
	var local: Player = source.get(local_peer_id)
	if local == null:
		local_hp_ratio = 1.0
		local_is_downed = false
		local_slot = 0
	else:
		var hp := _read_hp(local)
		local_hp_ratio = clampf(hp.x / float(maxi(hp.y, 1)), 0.0, 1.0)
		local_is_downed = local.is_downed
		local_slot = local.slot
	for peer_id: int in source.keys():
		if peer_id == local_peer_id:
			continue
		var player: Player = source[peer_id]
		var teammate := HudTeammate.new()
		teammate.peer_id = peer_id
		teammate.display_name = player.name
		teammate.slot = player.slot
		teammate.is_downed = player.is_downed
		var hp := _read_hp(player)
		teammate.hp_ratio = clampf(hp.x / float(maxi(hp.y, 1)), 0.0, 1.0)
		teammates.append(teammate)
	changed.emit()


## Fraction of `total` that is still left, clamped to [0, 1]; 0 when there is
## no cooldown to speak of. Drives the weapon-slot cooldown sweeps.
static func cooldown_fraction(time_left: float, total: float) -> float:
	if total <= 0.0:
		return 0.0
	return clampf(time_left / total, 0.0, 1.0)


func set_weapon_cooldown(slot_index: int, time_left: float, total: float) -> void:
	if slot_index < 0 or slot_index >= weapon_slots.size():
		push_warning("[hud] weapon slot %d out of range" % slot_index)
		return
	weapon_slots[slot_index].cooldown_fraction = cooldown_fraction(time_left, total)
	changed.emit()


## Marks exactly one slot as the active weapon (Events.weapon_swapped).
func set_weapon_active(slot_index: int) -> void:
	for index: int in weapon_slots.size():
		weapon_slots[index].active = index == slot_index
	changed.emit()


func set_floor_label(text: String) -> void:
	floor_label = text
	changed.emit()


## (current, max) HP for a player, read duck-typed from their Health child so
## the swap to Dev A's real Health (W2-A1) is mechanical. A missing Health or
## missing fields yields the full-bar fallback.
func _read_hp(player: Player) -> Vector2i:
	var health: Node = player.health
	if health == null:
		return Vector2i(DEFAULT_MAX_HP, DEFAULT_MAX_HP)
	var current_value: Variant = health.get("current_hp")
	var max_value: Variant = health.get("max_hp")
	if current_value is int and max_value is int:
		return Vector2i(maxi(int(current_value), 0), maxi(int(max_value), 1))
	return Vector2i(DEFAULT_MAX_HP, DEFAULT_MAX_HP)