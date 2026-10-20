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
## The group the enemies a SHOCK application chains to are found in. The real
## registrant is Dev A's `enemies-ai` enemy base — **blocked on Dev A (W4-A1)**
## — so today the group is whatever the world (or a test double) puts in it; the
## swap-in is Dev A's `add_to_group` line and nothing here changes.
const ENEMY_TAG: StringName = &"enemy"
## The `EffectHost` child a player carries (effect-system, W4-B2). Looked up by
## name under an entity so the two relic-driven rows below can ask a host what it
## holds without this component depending on the player scene.
const EFFECT_HOST_NODE: NodePath = ^"EffectHost"
## Statuses a player can never receive. SPEC-stats-status, "Status effects",
## last line: "Players can receive BURN, CHILL, TOXIN, BLEED from enemies and
## hazards, never MARK/UNRAVEL/FREEZE."
const PLAYER_FORBIDDEN: Array[int] = [Status.MARK, Status.UNRAVEL, Status.FREEZE]

## Stamped on every tick's `HitData` alongside the status's own name, so a
## listener can tell damage over time from a connecting hit. `Effect`'s `proc`
## tag is the precedent for a hit tag outside the `Tags` vocabulary: this one
## describes the carrier, not the content.
const STATUS_TAG: StringName = &"status"
## Stamped on the hit a SHOCK chains to another enemy, on top of `STATUS_TAG` and
## the status's name: a chain is a status result that travelled, and the debug
## overlay (W4-B11) reads the two apart.
const CHAIN_TAG: StringName = &"chain"

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

## SHOCK's chain, from SPEC-stats-status, SHOCK's row: "On apply, chains 30% of
## trigger damage to up to 2 enemies within 96 px; Lightning Rod +2 chains". The
## trigger damage is the hit that applied the shock, handed to `apply_status()`;
## an application with no trigger damage (a bare `apply_status(SHOCK, 1)`) lands
## the status and chains nothing.
const SHOCK_CHAIN_DAMAGE_FRACTION: float = 0.30
## How many enemies one application reaches before the Lightning Rod bonus.
const SHOCK_CHAIN_TARGETS: int = 2
## The radius the chain looks for its targets in, in pixels.
const SHOCK_CHAIN_RADIUS: float = 96.0
## The relic whose holder chains two enemies further, and what it adds. Read off
## the `EffectHost` that governs the application through `has_relic()` — never
## hard-coded into the chain count, so the relic stays data.
const LIGHTNING_ROD_ID: StringName = &"lightning_rod"
const LIGHTNING_ROD_CHAIN_BONUS: int = 2

## TOXIN's healing penalty, from its row: "healing received -50%". Exposed as
## `healing_multiplier()`, which the heal path multiplies the incoming amount by
## — a readable property rather than a number the healer has to know about.
const TOXIN_HEALING_MULTIPLIER: float = 0.5
## The relic that stops TOXIN's clock, from its row: "Plague Doctor's Mask
## disables expiry". Looked up by id on the governing `EffectHost`, the same way
## Lightning Rod is.
const PLAGUE_DOCTORS_MASK_ID: StringName = &"plague_doctors_mask"

## UNRAVEL's taken-damage bonus, from its row: "+10% all damage taken per
## stack". Read by `Damage.compute` through `damage_taken_multiplier()` and
## folded into the formula's `status_mult` term.
const UNRAVEL_DAMAGE_TAKEN_PER_STACK: float = 0.10

## CHILL's penalty per stack, as a `StatBlock` *percent* modifier on move and
## attack speed: SPEC-stats-status, "`-12% move and attack speed per stack`". A
## percent modifier rather than a flat one because the spec states the row as a
## fraction of the entity's own speed, and because the base values are never
## written (SPEC-project).
const CHILL_SLOW_PER_STACK: float = 0.12

## FREEZE's immobility, as the percent modifier that takes move speed to 0:
## `(base + flat) * (1 + percent)` is 0 when the percent sum is -1, whatever the
## base is. Move speed only — "cannot act" is `can_act()`, not a speed of zero,
## because attack speed is clamped at 0.2 and would never read as stopped.
const FREEZE_IMMOBILE_PERCENT: float = -1.0

## The `StatBlock` modifier sources CHILL and FREEZE own. One `StringName` each so
## `remove_source()` on a clear, an expiry, a stack change and a conversion all
## release exactly the modifiers that status added — and so a second status
## cannot take the first one's penalty away with it.
const CHILL_SOURCE: StringName = &"status:chill"
const FREEZE_SOURCE: StringName = &"status:freeze"

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
## Whether the pending FREEZE double is still unspent. Armed when FREEZE is
## applied (or when CHILL converts to it) and spent by `consume_freeze_double()`,
## which is what makes the double land on *one* hit. Without Permafrost the hit
## after that is a normal one; Permafrost's "always" is the attacker-side
## `status_mult` term on `Damage.compute` (G23), not a second flag here.
var _freeze_double_ready: bool = false


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
##
## `trigger_damage` is the damage of the hit that caused the application and is
## only read by SHOCK, whose row is "chains 30% of trigger damage to up to 2
## enemies within 96 px". It is a trailing optional argument, so the signature
## the spec fixes (`apply_status(status, stacks, source: Node)`) is unchanged for
## every caller that does not need it — a relic that applies a shock passes the
## hit's damage and one that applies a burn ignores it.
func apply_status(status: Status, stacks: int = 1, source: Node = null, trigger_damage: int = 0) -> bool:
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
	# SPEC-stats-status, CHILL's row: "At 5 converts to `FREEZE`" — the 5th stack
	# is never held as Chill. Only an entity that may hold FREEZE converts: a
	# player is one of the three statuses FREEZE is forbidden to, so a player
	# simply sits at the Chill cap (the spec's own last line, applied here rather
	# than left for the caller).
	if status == Status.CHILL and total >= CHILL_MAX_STACKS and allows(Status.FREEZE):
		return _freeze_from_chill(source)
	entry["stacks"] = total
	entry["remaining"] = duration(status)
	entry["source"] = source if is_instance_valid(source) else null
	if status == Status.FREEZE:
		_freeze_double_ready = true
	_sync_speed_modifiers(status)
	status_applied.emit(status, total)
	Events.status_applied.emit(entity(), status, total, source)
	if status == Status.SHOCK:
		_chain_shock(source, trigger_damage)
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
	_release_modifiers(status)
	status_expired.emit(status)


## Removes every active status, announcing each as it goes.
func clear_all() -> void:
	var present: Array[int] = _active.keys()
	for status: int in present:
		clear(status)


# --- the flags the other rows' consumers read (G21) --------------------------

## Whether the entity may act this frame. False only while FREEZE is active —
## SPEC-stats-status, FREEZE's row: "Immobile 2 s, can't act". The lock is a
## read, not a disrupted state: the entity's own controller asks before it moves
## or attacks (enemies-ai / abilities), so a frozen enemy keeps its AI and its
## cooldowns and simply produces nothing while this is false.
func can_act() -> bool:
	return not has(Status.FREEZE)


## Whether the pending FREEZE double is still unspent. `Damage.compute` (G23)
## reads it with the mark below to build `status_mult`.
func freeze_double_ready() -> bool:
	return has(Status.FREEZE) and _freeze_double_ready


## Spends the FREEZE double: true on the first hit after a freeze, false after.
## The spec's row is "next hit double damage once (...) then clears all Chill",
## so spending it is also what drops any Chill the frozen entity picked up.
func consume_freeze_double() -> bool:
	if not freeze_double_ready():
		return false
	_freeze_double_ready = false
	clear(Status.CHILL)
	return true


## Whether the entity's next damaging hit is a guaranteed crit. SPEC-stats-status,
## MARK's row: "Next damaging hit is a guaranteed crit, then consumed". Read by
## `Damage.compute` (G23), which short-circuits its crit roll when this is true.
func mark_forces_crit() -> bool:
	return has(Status.MARK)


## Consumes the mark, returning whether there was one to consume: the next
## damaging hit is the only caller, and it is consumed whether or not the hit
## itself connects (the spec says "next damaging hit", not "next hit that lands").
func consume_mark() -> bool:
	if not has(Status.MARK):
		return false
	clear(Status.MARK)
	return true


# --- the G22 rows' own reads and behaviour -----------------------------------

## The factor incoming healing is multiplied by: TOXIN's row, "healing received
## -50 %". 1.0 for an entity with no toxin. The heal path asks for this and
## multiplies the amount it was about to grant — the penalty is applied where
## the healing lands, so a caller cannot forget it and a test asserts the heal
## that arrived rather than the number here.
func healing_multiplier() -> float:
	return TOXIN_HEALING_MULTIPLIER if has(Status.TOXIN) else 1.0


## The factor every damaging hit against this entity is multiplied by: UNRAVEL's
## row, "+10 % all damage taken per stack". 1.0 with no UNRAVEL. `Damage.compute`
## reads it into the formula's `status_mult` term; Kindling's BURN term and
## Permafrost's FREEZE term are the attacker-side terms G23 adds beside this one.
func damage_taken_multiplier() -> float:
	return 1.0 + UNRAVEL_DAMAGE_TAKEN_PER_STACK * float(stacks(Status.UNRAVEL))


## True while the relic `id` is held by either effect host that governs this
## entity's statuses: the applier's (the usual case — the relic that applied the
## shock or the toxin is the player's) or, when the entity applied the status to
## itself, the entity's own host. Read off an `EffectHost` and never off a
## hard-coded number, so a relic stays an attachment rather than a code path.
func has_relic(id: StringName, source: Node = null) -> bool:
	for host: EffectHost in _effect_hosts(source):
		if host.has_effect(id):
			return true
	return false


## How many enemies one SHOCK application reaches: the spec's 2, plus
## `LIGHTNING_ROD_CHAIN_BONUS` when Lightning Rod is held. The relic adds to the
## count rather than replacing it, so a build without the relic chains exactly
## what the table says.
func chain_count(source: Node = null) -> int:
	var bonus := LIGHTNING_ROD_CHAIN_BONUS if has_relic(LIGHTNING_ROD_ID, source) else 0
	return SHOCK_CHAIN_TARGETS + bonus


## The damage one chained enemy takes: 30 % of the trigger damage, rounded.
## Zero for an application that carried none, which is what makes a bare
## `apply_status(SHOCK, 1)` land the status and chain nothing.
func chain_damage(trigger_damage: int) -> int:
	return roundi(float(maxi(trigger_damage, 0)) * SHOCK_CHAIN_DAMAGE_FRACTION)


## The enemies a SHOCK application chains to: the nearest ones to this entity
## within `SHOCK_CHAIN_RADIUS`, nearest first, at most `chain_count()` of them,
## and never this entity itself. The candidate set is the `ENEMY_TAG` group,
## which is where Dev A's enemies register (**blocked on Dev A (W4-A1)** for the
## real registrant; today it is whatever the world — or a test double — put
## there). An entity the component does not carry to, or one with no `Health`,
## is simply skipped by the delivery.
func chain_targets(source: Node = null) -> Array[Node]:
	var reachable: Array[Node] = []
	var tree := get_tree()
	if tree == null:
		return reachable
	var here := _entity_position()
	for candidate: Node in tree.get_nodes_in_group(ENEMY_TAG):
		if candidate == entity() or not is_instance_valid(candidate):
			continue
		var positioned := candidate as Node2D
		if positioned == null:
			continue
		if here.distance_to(positioned.global_position) <= SHOCK_CHAIN_RADIUS:
			reachable.append(positioned)
	reachable.sort_custom(_nearer_first)
	var chained: Array[Node] = []
	var limit: int = chain_count(source)
	for candidate: Node in reachable:
		if chained.size() >= limit:
			break
		chained.append(candidate)
	return chained


## The hit a chained enemy receives: the status tick's shape (the status's
## element, the `status` tag, the status's own name) plus `CHAIN_TAG`, so a
## listener can tell a shock that travelled from a burn that did not. No proc
## depth and no crit: a chain is a status result, not a chain link of effects.
func chain_hit(amount: int) -> HitData:
	var hit := tick_hit(Status.SHOCK, amount)
	hit.tags.append(CHAIN_TAG)
	return hit


## Runs SHOCK's chain for one application. Called from `apply_status()` and
## nowhere else, so the row has one implementation. A warning-free no-op when
## the application carried no damage, which is the common case for a fixture and
## a caller that applies a shock without a triggering hit.
func _chain_shock(source: Node, trigger_damage: int) -> void:
	var amount := chain_damage(trigger_damage)
	if amount <= 0:
		return
	for target: Node in chain_targets(source):
		_deliver_to(target, chain_hit(amount))


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
	if health_of(entity()) == null:
		if not _warned_missing_health:
			_warned_missing_health = true
			push_warning("[status] %s: no %s to receive status damage, ticks dropped" % [
				entity_name(), HEALTH_NODE])
		return false
	return _deliver_to(entity(), tick_hit(status, amount))


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
	return health_of(entity())


## The `Health` of any node, or null when it carries none. The one lookup every
## status result's damage goes through — the entity's own tick and a SHOCK
## chain's delivery to another enemy — so "who can receive status damage" is one
## decision rather than two.
func health_of(target: Node) -> Node:
	if target == null or not is_instance_valid(target):
		return null
	var node: Node = target.get_node_or_null(HEALTH_NODE)
	if node == null or not node.has_method(HEALTH_METHOD):
		return null
	return node


## Hands `hit` to `target`'s `Health`, returning whether a hit was delivered. A
## target with no `Health` is a silent skip rather than a warning: a chain lands
## on whatever the group put in range, and an enemy that carries no health yet is
## not this component's problem to report (SPEC-combat-core owns the real
## component — **blocked on Dev A (W2-A1)**).
func _deliver_to(target: Node, hit: HitData) -> bool:
	var sink: Node = health_of(target)
	if sink == null:
		return false
	sink.call(HEALTH_METHOD, hit)
	return true


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
			# SPEC-stats-status, TOXIN's row: "Plague Doctor's Mask disables
			# expiry". The mask re-arms the clock instead of letting the toxin
			# go, so a masked build's stacks persist and its bar still reads a
			# sane value; dropping the mask lets the re-armed window run out
			# naturally, which is what "disables expiry" means while it is held.
			if status == Status.TOXIN and has_relic(PLAGUE_DOCTORS_MASK_ID, entry.get("source") as Node):
				entry["remaining"] = duration(status)
			else:
				expired.append(status)
	for status: int in expired:
		clear(status)


# --- the row-specific edges (G21) --------------------------------------------

## Brings CHILL's or FREEZE's `StatBlock` modifiers in line with the stacks the
## component now holds: CHILL's -12 % per stack on move and attack speed, FREEZE's
## move speed of 0. One status's source is removed and re-added, so a stack change
## widens the penalty without stacking a second copy of it, and a status with no
## stacks leaves none behind. Every write is a modifier — `base` is never touched
## (SPEC-project: "Never edit base stats").
##
## Called from `apply_status()` and from the Chill-to-Freeze conversion, so there
## is one place a speed penalty is computed. An entity with no `StatBlock` yet
## simply has no stats to slow.
func _sync_speed_modifiers(status: int) -> void:
	var block := stat_block()
	if block == null:
		return
	match status:
		Status.CHILL:
			block.remove_source(CHILL_SOURCE)
			var held := stacks(Status.CHILL)
			if held > 0:
				var percent: float = -CHILL_SLOW_PER_STACK * float(held)
				block.add_modifier(StatBlock.Stat.MOVE_SPEED, 0.0, percent, CHILL_SOURCE)
				block.add_modifier(StatBlock.Stat.ATTACK_SPEED, 0.0, percent, CHILL_SOURCE)
		Status.FREEZE:
			block.remove_source(FREEZE_SOURCE)
			if has(Status.FREEZE):
				block.add_modifier(StatBlock.Stat.MOVE_SPEED, 0.0, FREEZE_IMMOBILE_PERCENT, FREEZE_SOURCE)
		_:
			pass


## Takes back the modifiers a status owns as it leaves, and forgets its pending
## double with it. The counterpart of `_sync_speed_modifiers()`, called from
## `clear()` and nowhere else, so no status can be removed with its penalty still
## on the entity — however it was removed (consumed, expired, converted, or an
## explicit `clear_all()`).
func _release_modifiers(status: int) -> void:
	var block := stat_block()
	match status:
		Status.CHILL:
			if block != null:
				block.remove_source(CHILL_SOURCE)
		Status.FREEZE:
			_freeze_double_ready = false
			if block != null:
				block.remove_source(FREEZE_SOURCE)
		_:
			pass


## CHILL reaching its cap becomes FREEZE instead: the Chill is cleared (with its
## slow) and the freeze is applied on top, carrying the full duration and arming
## the one-shot double. Announced like any other application, so a HUD icon and an
## effect listening on `Events.status_applied` see the freeze rather than a Chill
## that never existed.
##
## Called only from `apply_status()`, after the player gate has already decided
## this entity may hold FREEZE.
func _freeze_from_chill(source: Node) -> bool:
	clear(Status.CHILL)
	var entry: Dictionary = _entry(Status.FREEZE)
	entry["stacks"] = FREEZE_MAX_STACKS
	entry["remaining"] = FREEZE_DURATION
	_freeze_double_ready = true
	_sync_speed_modifiers(Status.FREEZE)
	status_applied.emit(Status.FREEZE, FREEZE_MAX_STACKS)
	Events.status_applied.emit(entity(), Status.FREEZE, FREEZE_MAX_STACKS, source)
	return true


## The effect hosts that govern this entity's statuses: the applier's first (the
## relic that applied the status belongs to the player who applied it), then the
## entity's own, if it carries one. Both are checked by `has_relic()`, so a relic
## is found whether the entity applied the status to itself or had it applied.
func _effect_hosts(source: Node) -> Array[EffectHost]:
	var hosts: Array[EffectHost] = []
	var applying := source as Effect
	if applying != null and is_instance_valid(applying.host):
		hosts.append(applying.host)
	var owner_entity := entity()
	if owner_entity == null:
		return hosts
	var own := owner_entity.get_node_or_null(EFFECT_HOST_NODE) as EffectHost
	if own != null and not hosts.has(own):
		hosts.append(own)
	return hosts


## This entity's position in the world, for the SHOCK radius measurement. Zero
## for an entity that carries no transform, which puts every candidate at its own
## distance from the origin rather than failing the chain.
func _entity_position() -> Vector2:
	var positioned := entity() as Node2D
	return Vector2.ZERO if positioned == null else positioned.global_position


## `sort_custom` predicate for the chain: true when `a` is nearer this entity
## than `b`.
func _nearer_first(a: Node, b: Node) -> bool:
	var here := _entity_position()
	var first := a as Node2D
	var second := b as Node2D
	return here.distance_squared_to(first.global_position) < here.distance_squared_to(second.global_position)


## The mutable record for `status`, created empty on first use. Dictionaries are
## references, so the caller writes straight into the table. `source` is the
## effect that applied the status, kept so a later tick can ask the same host the
## application asked (TOXIN's Plague Doctor's Mask exemption); it is null for an
## application that named none.
func _entry(status: int) -> Dictionary:
	if not _active.has(status):
		_active[status] = {"stacks": 0, "remaining": NO_EXPIRY, "carry": 0.0, "source": null}
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