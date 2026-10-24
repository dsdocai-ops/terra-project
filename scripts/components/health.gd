class_name Health
extends Node
## Hit points for any entity: player, enemy, boss, destructible. Owned by
## combat-core (SPEC-combat-core, "Components").
## Sync: host-authoritative. `current_hp` is replicated by the entity's
## StateSync; the fill ratio is mirrored into `StatBlock.current_hp_ratio` so
## clients render the same bar. Clients never call `apply_damage` or `heal`
## themselves: damage reaches here through `Hurtbox.receive` and `StatusEffects`
## ticks, both host-only.

## The hit landed and the target is still standing (or was saved by
## `about_to_die`).
signal damaged(hit: HitInfo)
signal healed(amount: int)
## Emitted before death is final. A handler (Second Wind, Undying, Twin Souls)
## sets `hit.prevented = true` to keep the target alive; `current_hp` is 0 during
## the emit so a handler may also `heal()` it back up.
signal about_to_die(hit: HitInfo)
signal died(hit: HitInfo)

## The `StatBlock` and `StatusEffects` siblings, looked up by the same names the
## player scene uses.
const STAT_BLOCK_NODE: NodePath = ^"../StatBlock"
const STATUS_NODE: NodePath = ^"../StatusEffects"
## HP an `about_to_die` prevention leaves behind when its handler did not heal.
const PREVENTED_DEATH_HP: int = 1
## Used when the entity has no `StatBlock` (a bare destructible).
const FALLBACK_MAX_HP: int = 1

var current_hp: int = 0
## `StatBlock.MAX_HP` as a whole number, at least 1. A property (not a method)
## because the HUD model reads `max_hp` and `current_hp` by name.
var max_hp: int:
	get:
		if _stats == null:
			return FALLBACK_MAX_HP
		return maxi(roundi(_stats.get_value(StatBlock.Stat.MAX_HP)), 1)
var is_dead: bool = false
## Healing multipliers keyed by source (Coward's Cloak and friends), multiplied
## together with the Toxin penalty. Host-only, like every modifier.
var _heal_multipliers: Dictionary[StringName, float] = {}
## Called with the excess when a heal overshoots max HP (Oracle shields turn it
## into a shield). Signature: `func(excess: int) -> void`.
var overheal_handler: Callable = Callable()

var _stats: StatBlock = null


func _ready() -> void:
	_stats = get_node_or_null(STAT_BLOCK_NODE) as StatBlock
	if _stats != null:
		_stats.stat_changed.connect(_on_stat_changed)
	current_hp = max_hp
	_sync_ratio()




## Applies a computed hit (`hit.final_damage`). Returns whether the entity took
## it: false for a null hit or an entity that is already dead.
func apply_damage(hit: HitInfo) -> bool:
	if hit == null or is_dead:
		return false
	var remaining: int = current_hp - maxi(hit.final_damage, 0)
	if remaining > 0:
		current_hp = remaining
		_sync_ratio()
		damaged.emit(hit)
		return true
	current_hp = 0
	hit.prevented = false
	about_to_die.emit(hit)
	if hit.prevented:
		current_hp = clampi(maxi(current_hp, PREVENTED_DEATH_HP), 0, max_hp)
		_sync_ratio()
		damaged.emit(hit)
		return true
	is_dead = true
	current_hp = 0
	_sync_ratio()
	damaged.emit(hit)
	died.emit(hit)
	return true


## Restores up to `amount` HP and returns what was granted. The amount passes
## through the Toxin penalty (`StatusEffects.healing_multiplier()`) and every
## `set_heal_multiplier` source first. What overshoots max HP goes to
## `overheal_handler`. The dead are not healed.
func heal(amount: int, source: Node = null) -> int:
	if is_dead or amount <= 0:
		return 0
	var scaled: int = floori(float(amount) * _heal_multiplier())
	var room: int = max_hp - current_hp
	var granted: int = mini(scaled, room)
	var excess: int = scaled - granted
	if excess > 0 and overheal_handler.is_valid():
		overheal_handler.call(excess)
	if granted <= 0:
		return 0
	current_hp += granted
	_sync_ratio()
	healed.emit(granted)
	var player := get_parent() as Player
	if player != null:
		Events.player_healed.emit(player, granted, source)
	return granted


## Sets (or, with 1.0, clears) one source's healing multiplier.
func set_heal_multiplier(source: StringName, multiplier: float) -> void:
	if is_equal_approx(multiplier, 1.0):
		_heal_multipliers.erase(source)
	else:
		_heal_multipliers[source] = multiplier


## Fills HP to max. Spawn setup calls it once the entity's base stats are in.
func refill() -> void:
	current_hp = max_hp
	_sync_ratio()


## Brings a dead entity back at `hp` (revives, test setup). Host-only.
func revive(hp: int) -> void:
	is_dead = false
	current_hp = clampi(hp, 1, max_hp)
	_sync_ratio()


func _heal_multiplier() -> float:
	var product: float = 1.0
	var statuses := get_node_or_null(STATUS_NODE) as StatusEffects
	if statuses != null:
		product *= statuses.healing_multiplier()
	for factor: float in _heal_multipliers.values():
		product *= factor
	return product


func _sync_ratio() -> void:
	if _stats != null:
		_stats.current_hp_ratio = float(current_hp) / float(max_hp)


## A max-HP modifier keeps the fill ratio (StatBlock's rule), so current HP
## follows it; a lowered cap never leaves current above max.
func _on_stat_changed(stat: StatBlock.Stat, _value: float) -> void:
	if stat != StatBlock.Stat.MAX_HP or is_dead:
		return
	current_hp = clampi(roundi(_stats.current_hp_ratio * float(max_hp)), 1, max_hp)
