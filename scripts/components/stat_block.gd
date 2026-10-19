class_name StatBlock
extends Node
## Base + flat + percent stat math for every entity in the game. Owned by
## stats-status.
## Sync: modifier lists are host-only; the HUD reads get_value() from the
## local player's replicated snapshot (the host sends the 11 values in
## StateSync). The current-HP ratio is replicated alongside so clients render
## the same fill.
##
## Value = (base + sum(flat)) * (1 + sum(percent)), clamped per stat
## (CRIT_CHANCE 0 to 1, COOLDOWN_REDUCTION max 0.6, ATTACK_SPEED min 0.2).
## Base values are never written after _ready except by set_base() during
## spawn setup; every other change is a modifier carrying a handle.

enum Stat {
	MAX_HP,
	ATTACK,
	DEFENSE,
	MOVE_SPEED,
	ATTACK_SPEED,
	DODGE_COOLDOWN,
	CRIT_CHANCE,
	CRIT_DAMAGE,
	ABILITY_POWER,
	COOLDOWN_REDUCTION,
	LUCK,
}

signal stat_changed(stat: Stat, value: float)

const STAT_COUNT: int = 11
const CRIT_CHANCE_MIN: float = 0.0
const CRIT_CHANCE_MAX: float = 1.0
const COOLDOWN_REDUCTION_MAX: float = 0.6
const ATTACK_SPEED_MIN: float = 0.2

## Stat -> float, filled from CharacterData/ClassData/EnemyData.
@export var base: Dictionary = {}

## Fraction of MAX_HP that is "current", kept in sync by Health (combat-core).
## A MAX_HP change (modifier or set_base) never touches it, so the fill ratio
## survives level-ups and max-HP modifiers.
var current_hp_ratio: float = 1.0

var _next_handle: int = 1
## {handle: int, stat: Stat, flat: float, percent: float, source: StringName}
var _modifiers: Array[Dictionary] = []


func get_value(stat: Stat) -> float:
	var flat := 0.0
	var percent := 0.0
	for modifier: Dictionary in _modifiers:
		if int(modifier["stat"]) == stat:
			flat += float(modifier["flat"])
			percent += float(modifier["percent"])
	var value := (float(base.get(stat, 0.0)) + flat) * (1.0 + percent)
	return _clamp(stat, value)


## Adds a modifier and returns a handle for remove_modifier().
func add_modifier(stat: Stat, flat: float, percent: float, source: StringName) -> int:
	var handle := _next_handle
	_next_handle += 1
	_modifiers.append({
		"handle": handle,
		"stat": stat,
		"flat": flat,
		"percent": percent,
		"source": source,
	})
	_emit_changed(stat)
	return handle


## Removes exactly the modifier with this handle. Unknown handles are a no-op.
func remove_modifier(handle: int) -> void:
	for i in _modifiers.size():
		if int(_modifiers[i]["handle"]) == handle:
			var stat: Stat = int(_modifiers[i]["stat"])
			_modifiers.remove_at(i)
			_emit_changed(stat)
			return


## Removes every modifier contributed by one relic/node/status source.
func remove_source(source: StringName) -> void:
	var changed: Array[int] = []
	for i in range(_modifiers.size() - 1, -1, -1):
		if StringName(_modifiers[i]["source"]) == source:
			var stat: Stat = int(_modifiers[i]["stat"])
			changed.append(stat)
			_modifiers.remove_at(i)
	for raw_stat: int in changed:
		_emit_changed(raw_stat)


## Stat -> value, for Hollow You and the debug console.
func snapshot() -> Dictionary:
	var out := {}
	for stat: Stat in Stat.values():
		out[stat] = get_value(stat)
	return out


## Writes a base value; used only during spawn setup. Keeps current_hp_ratio.
func set_base(stat: Stat, value: float) -> void:
	base[stat] = value
	_emit_changed(stat)


func _clamp(stat: Stat, value: float) -> float:
	match stat:
		Stat.CRIT_CHANCE:
			return clampf(value, CRIT_CHANCE_MIN, CRIT_CHANCE_MAX)
		Stat.COOLDOWN_REDUCTION:
			return minf(value, COOLDOWN_REDUCTION_MAX)
		Stat.ATTACK_SPEED:
			return maxf(value, ATTACK_SPEED_MIN)
		_:
			return value


func _emit_changed(stat: Stat) -> void:
	stat_changed.emit(stat, get_value(stat))
