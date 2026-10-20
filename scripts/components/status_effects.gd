class_name StatusEffects
extends Node
## The status-effect component every damageable entity carries (stats-status).
## Owned by stats-status.
##
## Sync: host only. The application, the stack counts, the durations, the
## ticking damage and (from W4-B4's later goals) the element combos are decided
## on the host, and only a peer that resolves statuses deals status damage
## (`_resolves_statuses()`, the seam `EffectHost._can_spawn()` uses). What
## clients see is SPEC-stats-status "Multiplayer ownership": "`StatusEffects`
## stacks are replicated by the entity's `StateSync` so clients can render icons
## and tints. Modifier lists are host-only; the HUD reads `get_value()` from the
## local player's replicated snapshot (the host sends the 11 values in
## `StateSync`)." Replicating the stacks is a property on the entity's
## `StateSync` in its scene and lands with the HUD status icons (W4-B10, G51) —
## **blocked on Dev A (W2-A1, player.tscn)** for the player, whose
## `StatusEffects` node is still bare today.
##
## Ticking is scaled, never `Engine.time_scale`: `_physics_process` multiplies
## its delta by `TimeManager.scale_for(entity)`, so a time stop aimed at the
## enemies freezes a burning enemy's damage with it (SPEC-time-manager). The
## entity's kind is never guessed from a script class — `is_player()` reads the
## `PLAYER_TAG` group the entity joined (networking's `PlayerSpawner` tags every
## player it spawns).

enum Status {
	BURN,
	CHILL,
	FREEZE,
	SHOCK,
	TOXIN,
	MARK,
	BLEED,
	UNRAVEL,
}

signal status_applied(status: Status, stacks: int)
signal status_expired(status: Status)

## The `StatBlock` child the tick fraction is taken from (the player scene's
## component layout). A bare node there is a missing component, not a crash.
const STAT_BLOCK_NODE: NodePath = ^"StatBlock"
## The `Health` child a tick's damage is handed to (combat-core, W2-A1).
const HEALTH_NODE: NodePath = ^"Health"
## Health's one entry point for damage: `apply_damage(hit: HitInfo)`
## (SPEC-combat-core, "Interfaces provided"). Called dynamically because the
## component is Dev A's and does not exist yet.
const HEALTH_METHOD: StringName = &"apply_damage"

## The group a player entity joins. `is_player()` reads it, so the player gate
## below never names a script class (SPEC-project: modules are consumed through
## their interface). `PlayerSpawner` tags every player it spawns; an entity with
## no tag is treated as an enemy — the permissive default, so an enemy double or
## an untagged fixture behaves exactly as the spec's table says.
const PLAYER_TAG: StringName = &"player"
## Statuses a player can never receive. SPEC-stats-status, "Status effects",
## last line: "Players can receive BURN, CHILL, TOXIN, BLEED from enemies and
## hazards, never MARK/UNRAVEL/FREEZE."
const PLAYER_FORBIDDEN: Array[int] = [Status.MARK, Status.UNRAVEL, Status.FREEZE]

## Stamped on every tick's `HitData` alongside the status's own name, so a
## listener can tell damage over time from a connecting hit. `Effect`'s `proc`
## tag is the precedent for a hit tag outside the `Tags` vocabulary: this one
## describes the carrier, not the content.
const STATUS_TAG: StringName = &"status"

## Stack cap meaning "no cap" (TOXIN's "unlimited stacks").
const UNLIMITED_STACKS: int = -1
## Duration meaning "no timer": the status lasts until something consumes it.
## MARK is consumed by the next damaging hit that lands on the entity (G21).
const NO_EXPIRY: float = 0.0
## Slack added before flooring a tick's accrued damage, so a float shortfall of
## a millionth of a point does not swallow a whole point of damage.
const DAMAGE_EPSILON: float = 0.000001
## How still an entity has to be for BLEED to stop ticking: its `velocity`
## squared, below which it counts as stationary.
const MOVE_EPSILON_SQUARED: float = 0.01
## The property a moving entity's velocity is read through (BLEED). Read off the
## entity as a plain Vector2 — every moving entity in the game is a
## `CharacterBody2D` or carries one — so nothing here names a class.
const VELOCITY_PROPERTY: StringName = &"velocity"

## Stack caps from the spec's "Stacking" column, one named constant each.
const BURN_MAX_STACKS: int = 5
const CHILL_MAX_STACKS: int = 5
const FREEZE_MAX_STACKS: int = 1
const SHOCK_MAX_STACKS: int = 1
const TOXIN_MAX_STACKS: int = UNLIMITED_STACKS
const MARK_MAX_STACKS: int = 1
const BLEED_MAX_STACKS: int = 10
const UNRAVEL_MAX_STACKS: int = 5

## Durations in seconds. The spec fixes BURN (4 s), FREEZE (2 s) and TOXIN
## (6 s); CHILL, SHOCK, BLEED and UNRAVEL are the week-12 balance pass's
## starting values (SPEC-stats-status, "Open questions"), and MARK's 0 is
## `NO_EXPIRY`.
const BURN_DURATION: float = 4.0
const CHILL_DURATION: float = 4.0
const FREEZE_DURATION: float = 2.0
const SHOCK_DURATION: float = 4.0
const TOXIN_DURATION: float = 6.0
const MARK_DURATION: float = NO_EXPIRY
const BLEED_DURATION: float = 4.0
const UNRAVEL_DURATION: float = 4.0

## Damage per second as a fraction of the entity's max HP, per stack, for the
## statuses whose behaviour is a tick. CHILL, FREEZE, SHOCK, MARK and UNRAVEL
## carry no tick: they change stats, flags or the next hit instead (G21, G22).
const BURN_DAMAGE_PER_SECOND: float = 0.04
const TOXIN_DAMAGE_PER_SECOND: float = 0.015
const BLEED_DAMAGE_PER_SECOND: float = 0.02

## The spec's seven rows plus FREEZE, by their snake_case names: the tag each
## tick carries and the word the debug overlay and the HUD use.
const STATUS_NAMES: Dictionary[int, StringName] = {
	Status.BURN: &"burn",
	Status.CHILL: &"chill",
	Status.FREEZE: &"freeze",
	Status.SHOCK: &"shock",
	Status.TOXIN: &"toxin",
	Status.MARK: &"mark",
	Status.BLEED: &"bleed",
	Status.UNRAVEL: &"unravel",
}

## The spec's element column, as `HitData.Element` (stats-status's own enum, the
## week-2 mirror of combat-core's `HitInfo.Element`). The tick's element is read
## from here, and W4-B4's combo rules (G24) key off exactly this table.
const STATUS_ELEMENT: Dictionary[int, int] = {
	Status.BURN: HitData.Element.FIRE,
	Status.CHILL: HitData.Element.FROST,
	Status.FREEZE: HitData.Element.FROST,
	Status.SHOCK: HitData.Element.STORM,
	Status.TOXIN: HitData.Element.POISON,
	Status.MARK: HitData.Element.SHADOW,
	Status.BLEED: HitData.Element.BLOOD,
	Status.UNRAVEL: HitData.Element.VOID,
}

const STATUS_MAX_STACKS: Dictionary[int, int] = {
	Status.BURN: BURN_MAX_STACKS,
	Status.CHILL: CHILL_MAX_STACKS,
	Status.FREEZE: FREEZE_MAX_STACKS,
	Status.SHOCK: SHOCK_MAX_STACKS,
	Status.TOXIN: TOXIN_MAX_STACKS,
	Status.MARK: MARK_MAX_STACKS,
	Status.BLEED: BLEED_MAX_STACKS,
	Status.UNRAVEL: UNRAVEL_MAX_STACKS,
}

const STATUS_DURATION: Dictionary[int, float] = {
	Status.BURN: BURN_DURATION,
	Status.CHILL: CHILL_DURATION,
	Status.FREEZE: FREEZE_DURATION,
	Status.SHOCK: SHOCK_DURATION,
	Status.TOXIN: TOXIN_DURATION,
	Status.MARK: MARK_DURATION,
	Status.BLEED: BLEED_DURATION,
	Status.UNRAVEL: UNRAVEL_DURATION,
}

const STATUS_DAMAGE_PER_SECOND: Dictionary[int, float] = {
	Status.BURN: BURN_DAMAGE_PER_SECOND,
	Status.TOXIN: TOXIN_DAMAGE_PER_SECOND,
	Status.BLEED: BLEED_DAMAGE_PER_SECOND,
}

## Status -> {stacks: int, remaining: float, carry: float}. Only active statuses
## are keys; `carry` is the fraction of a tick's damage not yet dealt.
var _active: Dictionary[int, Dictionary] = {}
## True once this component has warned that its entity carries no `Health`, so
## sixty frames of a burning enemy write one line and not sixty.
var _warned_missing_health: bool = false


# --- the API SPEC-stats-status's "Interfaces provided" fixes -------------------

## Applies `stacks` of `status`, and returns whether it landed. The stacks add
## up to the status's cap (`UNLIMITED_STACKS` for TOXIN) and the duration is
## **refreshed** rather than accumulated, which is the spec's own wording for
## BURN ("refresh duration, stacks add DPS") and the reading applied to every
## row. `source` is the effect or system that applied it and only ever names the
## origin on the bus, which is the likely-caller path: `Effect.apply_status`
## calls this, so `Effect` is the usual source.
##
## Refused, with nothing applied and nothing announced:
## - a `status` that is not a `Status` (warned: it is a programming error, not a
##   game state);
## - `stacks <= 0`;
## - a status in `PLAYER_FORBIDDEN` when the entity carries `PLAYER_TAG` (the
##   spec's last line, routinely reached and therefore silent);
## - every application on a peer that does not resolve statuses.
func apply_status(status: Status, stacks: int = 1, source: Node = null) -> bool:
	if not _is_known(status):
		push_warning("[status] %s: unknown status id %d refused" % [entity_name(), status])
		return false
	if stacks <= 0:
		return false
	if not allows(status):
		return false
	if not _resolves_statuses():
		return false
	var entry: Dictionary = _entry(status)
	var total: int = int(entry["stacks"]) + stacks
	var cap: int = max_stacks(status)
	if cap != UNLIMITED_STACKS:
		total = mini(total, cap)
	entry["stacks"] = total
	entry["remaining"] = duration(status)
	status_applied.emit(status, total)
	Events.status_applied.emit(entity(), status, total, source)
	return true


## Whether the entity carries `status` with at least one stack.
func has(status: Status) -> bool:
	var entry: Dictionary = _active.get(status, {}) as Dictionary
	return int(entry.get("stacks", 0)) > 0


## The entity's stacks of `status`, or 0 when it does not carry it.
func stacks(status: Status) -> int:
	var entry: Dictionary = _active.get(status, {}) as Dictionary
	return int(entry.get("stacks", 0))


## The scaled seconds `status` has left, or 0 for a status the entity does not
## carry and for one with no timer (`MARK_DURATION`).
func remaining(status: Status) -> float:
	var entry: Dictionary = _active.get(status, {}) as Dictionary
	return float(entry.get("remaining", NO_EXPIRY))


## Removes `status` and announces it. A status the entity does not carry is a
## no-op: there is no expiry to report.
func clear(status: Status) -> void:
	if not _active.has(status):
		return
	_active.erase(status)
	status_expired.emit(status)


## Removes every active status, announcing each as it goes.
func clear_all() -> void:
	var present: Array[int] = _active.keys()
	for status: int in present:
		clear(status)


# --- reads for the rest of the game ------------------------------------------

## The statuses the entity currently carries, in enum order.
func active_statuses() -> Array[int]:
	var found: Array[int] = []
	for status: int in Status.values():
		if has(status):
			found.append(status)
	return found


## The entity this component belongs to: the node the statuses are on, which is
## the node the time groups and the world refer to.
func entity() -> Node:
	return get_parent()


## Whether the entity is a player. Read off the entity's `PLAYER_TAG` group,
## never off a script class.
func is_player() -> bool:
	var owner_entity := entity()
	return owner_entity != null and owner_entity.is_in_group(PLAYER_TAG)


## Whether this entity may be given `status` at all: every status except the
## three the spec forbids players, and only those three when it is a player.
func allows(status: Status) -> bool:
	if not _is_known(status):
		return false
	if not is_player():
		return true
	return not PLAYER_FORBIDDEN.has(status)


func max_stacks(status: Status) -> int:
	return STATUS_MAX_STACKS.get(status, 0)


func duration(status: Status) -> float:
	return STATUS_DURATION.get(status, NO_EXPIRY)


## The name a status is known by, or an empty name for an unknown id.
func status_name(status: Status) -> StringName:
	return STATUS_NAMES.get(status, &"")


## The entity's name for a warning, or a stand-in when it is not wired yet.
func entity_name() -> String:
	var owner_entity := entity()
	return "unparented" if owner_entity == null else String(owner_entity.name)


## The damage `status` deals per second at `stacks`: a fraction of the entity's
## max HP (BURN 4 % per stack, TOXIN 1.5 %, BLEED 2 %). Zero for a status with
## no tick of its own, and zero for BLEED while the entity is still —
## SPEC-stats-status: "While the target moves, 2 % max HP per second per stack".
func damage_per_second(status: Status, stacks: int) -> float:
	var fraction: float = STATUS_DAMAGE_PER_SECOND.get(status, 0.0)
	if fraction <= 0.0 or stacks <= 0:
		return 0.0
	if status == Status.BLEED and not is_moving():
		return 0.0
	return max_hp() * fraction * float(stacks)


## The entity's max HP, the base every tick fraction is taken from. Read from
## the `StatBlock`, never from `Health`: a status tick needs no component but
## this one. 0 when the entity carries no StatBlock, which then ticks nothing.
func max_hp() -> float:
	var block := stat_block()
	return 0.0 if block == null else block.get_value(StatBlock.Stat.MAX_HP)


## The entity's `StatBlock`, or null when it has none yet.
func stat_block() -> StatBlock:
	var owner_entity := entity()
	if owner_entity == null:
		return null
	return owner_entity.get_node_or_null(STAT_BLOCK_NODE) as StatBlock


## Whether the entity is moving, for BLEED. Read off the entity's `velocity`
## when it carries one; an entity with no velocity reads as still (G22 pins the
## stationary-versus-moving pair).
func is_moving() -> bool:
	var owner_entity := entity()
	if owner_entity == null:
		return false
	var value: Variant = owner_entity.get(VELOCITY_PROPERTY)
	if value == null or not (value is Vector2):
		return false
	var velocity: Vector2 = value
	return velocity.length_squared() > MOVE_EPSILON_SQUARED


## Hands one tick's damage to the entity's `Health`, as a finished hit: the
## amount is an outcome of the tick, not a formula input, so it bypasses
## `Damage.compute`. The `Hurtbox` is bypassed too, on purpose — damage over time
## is not a connecting attack, so it takes no i-frames, rolls no crit and wakes
## no on-hit effect. Returns whether a hit was delivered; a missing `Health` is
## warned once per component, never once per tick (SPEC-combat-core owns the
## real component — **blocked on Dev A (W2-A1)**).
func deal_status_damage(status: Status, amount: int) -> bool:
	if amount <= 0:
		return false
	var sink: Node = health_component()
	if sink == null:
		if not _warned_missing_health:
			_warned_missing_health = true
			push_warning("[status] %s: no %s to receive status damage, ticks dropped" % [
				entity_name(), HEALTH_NODE])
		return false
	sink.call(HEALTH_METHOD, tick_hit(status, amount))
	return true


## The `HitData` a tick hands over: the amount as both `base_damage` and
## `final_damage` (so whichever of the two the real `Health` reads, the number
## is the tick's), the status's element, and the `status` tag plus the status's
## own name. No proc depth and no crit: a tick is not a chain link and cannot
## crit.
func tick_hit(status: Status, amount: int) -> HitData:
	var hit := HitData.new()
	hit.base_damage = float(amount)
	hit.final_damage = amount
	hit.element = STATUS_ELEMENT.get(status, HitData.Element.NONE)
	hit.tags = [STATUS_TAG, status_name(status)]
	return hit


## The entity's `Health`, or null when it carries none. A `has_method` check
## rather than a typed cast because the component is Dev A's and does not exist
## yet.
func health_component() -> Node:
	var owner_entity := entity()
	if owner_entity == null:
		return null
	var node: Node = owner_entity.get_node_or_null(HEALTH_NODE)
	if node == null or not node.has_method(HEALTH_METHOD):
		return null
	return node


# --- ticking ----------------------------------------------------------------

## Advances every active status by this frame's **scaled** time: counts the
## duration down, deals the damage whose fraction has accrued, and expires what
## ran out. This is how a time stop freezes a burning enemy's damage: the delta
## is scaled by the entity's `TimeManager` factor, which is 0 while it is
## stopped, so nothing ages and nothing is dealt.
func _physics_process(delta: float) -> void:
	if _active.is_empty():
		return
	if not _resolves_statuses():
		return
	var scale := TimeManager.scale_for(entity())
	if scale <= 0.0:
		return
	_tick(delta * scale)


func _tick(scaled_delta: float) -> void:
	var expired: Array[int] = []
	for status: int in _active.keys():
		var entry: Dictionary = _active[status]
		var remaining: float = float(entry["remaining"])
		if remaining > 0.0:
			remaining = maxf(remaining - scaled_delta, 0.0)
			entry["remaining"] = remaining
		var carry: float = float(entry["carry"]) \
			+ damage_per_second(status, int(entry["stacks"])) * scaled_delta
		var whole := floori(carry + DAMAGE_EPSILON)
		if whole > 0:
			carry -= float(whole)
			deal_status_damage(status, whole)
		entry["carry"] = carry
		if remaining <= 0.0 and duration(status) > NO_EXPIRY:
			expired.append(status)
	for status: int in expired:
		clear(status)


## The mutable record for `status`, created empty on first use. Dictionaries are
## references, so the caller writes straight into the table.
func _entry(status: int) -> Dictionary:
	if not _active.has(status):
		_active[status] = {"stacks": 0, "remaining": NO_EXPIRY, "carry": 0.0}
	return _active[status] as Dictionary


func _is_known(status: int) -> bool:
	return STATUS_NAMES.has(status)


## Whether this peer resolves statuses at all. SPEC-stats-status, "Multiplayer
## ownership": "All computation on the host." Split out so a client copy can
## flip it in one process — the same seam `EffectHost._can_spawn()` exposes, and
## the reason the client half is a unit test rather than only a two-instance
## smoke step.
func _resolves_statuses() -> bool:
	return multiplayer.is_server()