class_name StatusEffects
extends Node
## The status-effect component every damageable entity carries (stats-status).
## Owned by stats-status.
##
## Sync: host only. The application, the stack counts, the durations, the
## ticking damage and the six element combos (G24) are decided on the host, and
## only a peer that resolves statuses deals status damage
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
## Ticking is scaled, never the engine's own time scale: `_physics_process`
## multiplies its delta by `TimeManager.scale_for(entity)`, so a time stop aimed
## at the enemies freezes a burning enemy's damage with it (SPEC-time-manager).
## The entity's kind is never guessed from a script class — `is_player()` reads
## the `PLAYER_TAG` group the entity joined (networking's `PlayerSpawner` tags
## every player it spawns).
##
## Boss resists are data, not a code path: `status_resistance` is the field
## SPEC-bosses' `BossData` hands its "duration multiplier, Freeze downgraded to
## Chill" to, and every application goes through `resisted_duration()` or the
## `degrades_freeze()` branch, so a boss's number changes durations and nothing
## else. The formula's whole target-side term is likewise one read —
## `incoming_damage_multiplier()`, which `Damage.compute` calls — so Kindling,
## Permafrost and UNRAVEL are composed in one place rather than at the call site.

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

## Stamped on every tick's `HitInfo` alongside the status's own name, so a
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

# --- the six element combos (SPEC-stats-status, "Element combos") ------------
#
# "When a status is applied to a target that already has another element's
# status, the combo fires once, consumes the listed stacks, and emits
# `Events.combo_triggered`." The pair rules are `_combo_for()`; the numbers the
# table's Effect column names are here, one constant each, so no combo carries a
# literal and the week-12 balance pass edits this block and the table together.

## SHATTER's burst — "Burst 200% of trigger damage in 64 px, consumes
## Chill/Freeze" — as a fraction of the trigger damage and a radius in pixels.
const SHATTER_BURST_FRACTION: float = 2.0
const SHATTER_RADIUS: float = 64.0
## BLIGHT_EXPLOSION — "Explosion 40% per Toxin stack, consumes Toxin". The row
## does not say 40 % of *what*, and names no radius: the reading here is 40 % of
## the trigger damage per stack (the reference SHATTER's row states explicitly)
## and a detonation on the toxined target itself rather than an unspecified
## area. Recorded as a HANDOFF decision so the balance pass can correct it.
const BLIGHT_PER_STACK: float = 0.4
## SUPERCONDUCT — "-30% Defense for 8 s" — as a `StatBlock` percent modifier
## under `SUPERCONDUCT_SOURCE` and the window it is held for.
const SUPERCONDUCT_DEFENSE: float = -0.30
const SUPERCONDUCT_SECONDS: float = 8.0
## HEMORRHAGE's window — "Bleed ticks crit for 4 s".
const HEMORRHAGE_SECONDS: float = 4.0
## COLLAPSE's reach — "Pull enemies within 128 px to the target".
const COLLAPSE_RADIUS: float = 128.0
## The value `_combo_for()` returns when an application is not a reaction.
const NO_COMBO: int = -1

## The `StatBlock` modifier source SUPERCONDUCT owns, released when its 8 s runs
## out or the target's combos are cleared: the same per-source shape CHILL and
## FREEZE use, so one combo ending cannot take another's penalty with it.
const SUPERCONDUCT_SOURCE: StringName = &"combo:superconduct"
## The multiplier a HEMORRHAGE-window Bleed tick's damage is scaled by. A status
## tick bypasses `Damage.compute` (no roll, no `CRIT_DAMAGE`), so the crit and
## its doubling are one decision here rather than a formula call.
const COMBO_CRIT_MULTIPLIER: float = 2.0
## The factor `combo_damage_multiplier()` starts from and returns when nothing
## contributes: a build with neither consumer multiplies a combo's damage by
## exactly one.
const COMBO_DAMAGE_BASE: float = 1.0
## SPEC-stats-status, "Element combos", last line: "Reactive skill node (+40%)
## and Elementalist synergy (x2) multiply combo damage." Both numbers are here,
## named for the system that owns them, because neither system exists yet —
## Reactive is a week-7 skill node (progression-trees), Elementalist is a week-8
## synergy (SynergyTracker) — so the constants are the one place the spec's
## numbers live until the real consumers attach and read them.
const COMBO_ELEMENTALIST_MULTIPLIER: float = 2.0
const COMBO_REACTIVE_BONUS: float = 0.40
## The method an attached effect exposes to multiply combo damage: SPEC-effect-
## system's own seam shape (`connected_water_targets`, `pull_toward`), read off
## the applying entity's `EffectHost`. The hook is the **method**, never a relic
## id, so a component that does not know a synergy's name can still be changed by
## it; the real consumers attach to the player's host at spawn.
const COMBO_MULTIPLIER_METHOD: StringName = &"combo_damage_multiplier"
## Stamped on a combo's own damage alongside the combo's name, so a listener can
## tell a reaction's hit from a weapon's or a status tick's — `STATUS_TAG`'s
## precedent, for the debug overlay rather than for a rule.
const COMBO_TAG: StringName = &"combo"
## The property a `wet` entity exposes: SPEC-stats-status, CONDUCT's trigger,
## "Storm on a `wet` target (standing in water tile or Drowned enemy)". The world
## owns it — floor-generation's water tiles and Dev A's `Drowned` enemy — so an
## entity without the property reads as dry and nothing here names a class
## (**blocked on Dev A (W4-A1)**).
const WET_PROPERTY: StringName = &"wet"
## The method CONDUCT asks an entity for the enemies touching its connected water
## area — the spread half of the row. The real query is floor-generation's /
## enemies-ai's and does not exist yet (**blocked on Dev A (W2-A1, water
## tiles)**), so an entity without the method spreads nothing and the request
## itself is what the case asserts.
const WATER_AREA_METHOD: StringName = &"connected_water_targets"
## The method COLLAPSE asks each in-range enemy for the pull it must make toward
## the target. The movement is Dev A's enemy body (**blocked on Dev A (W4-A1)**),
## so the request is what the case asserts and nothing here moves a node.
const PULL_METHOD: StringName = &"pull_toward"

## Kindling's bonus, from SPEC-stats-status's formula: "+0.25 Kindling on BURN".
## An *attacker*-side term: it is added when the entity that dealt the hit holds
## the relic, which is why `Damage.compute` hands this component the attacking
## entity's `EffectHost` to read it from.
const KINDLING_ID: StringName = &"kindling"
const KINDLING_BURN_BONUS: float = 0.25
## Permafrost's bonus, from the same line: "+1.0 Permafrost on FREEZE, once".
## The one-shot half of "once" is the pending freeze double; the relic is what
## makes the bonus land on *every* hit against a frozen target.
const PERMAFROST_ID: StringName = &"permafrost"
const FREEZE_DAMAGE_BONUS: float = 1.0

## What `status_resistance` means at its default: a duration multiplier of 1.0 is
## "no resistance", so every entity that is not a boss runs exactly the table's
## own durations. SPEC-bosses, `BossData`: "duration multiplier".
const DEFAULT_STATUS_RESISTANCE: float = 1.0
## The resistance at or below which FREEZE degrades: SPEC-stats-status, "Freeze
## becomes heavy Chill". The comparison is `<=` rather than `==` so a malformed
## negative multiplier cannot smuggle a real freeze past the downgrade.
const NO_STATUS_RESISTANCE: float = 0.0
## The stacks a degraded FREEZE lands as Chill with — the Chill table's own cap,
## i.e. the heaviest Chill it allows.
const HEAVY_CHILL_STACKS: int = CHILL_MAX_STACKS

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

## The spec's element column, as `HitInfo.Element` (combat-core's `HitInfo.Element`). The tick's element is read
## from here, and W4-B4's combo rules (G24) key off exactly this table.
const STATUS_ELEMENT: Dictionary[int, int] = {
	Status.BURN: HitInfo.Element.FIRE,
	Status.CHILL: HitInfo.Element.FROST,
	Status.FREEZE: HitInfo.Element.FROST,
	Status.SHOCK: HitInfo.Element.STORM,
	Status.TOXIN: HitInfo.Element.POISON,
	Status.MARK: HitInfo.Element.SHADOW,
	Status.BLEED: HitInfo.Element.BLOOD,
	Status.UNRAVEL: HitInfo.Element.VOID,
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
## Combo -> the scaled seconds left of the combo's own lasting effect. Only the
## two rows whose Effect column names a duration are ever keys (HEMORRHAGE's 4 s,
## SUPERCONDUCT's 8 s); every other combo lands and is done. Ticked in
## `_physics_process` beside the statuses, on the same scaled time, so a time
## stop aimed at the enemies freezes a superconductor's clock with them.
var _combo_remaining: Dictionary[int, float] = {}

## How long a status lasts on this entity, as a multiplier on the table's own
## duration: SPEC-bosses' `BossData.status_resistance` — "duration multiplier,
## Freeze downgraded to Chill" — is where a boss's number comes from, and this
## is the field it is set on. Exported so a boss's spawn path (bosses' lane) sets
## it from data, and settable at run time so a phase can raise it.
##
## 1.0 is the default and means the spec's table rows run unmodified, which is
## what every non-boss entity wants. At or below `NO_STATUS_RESISTANCE` the
## durations are multiplied to nothing *and* FREEZE is downgraded — see
## `degrades_freeze()`: the downgrade exists so that "0.0 resistance" is a boss
## taking heavy Chill rather than a boss on which Freeze does nothing at all.
@export var status_resistance: float = DEFAULT_STATUS_RESISTANCE


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
	# The combo table is read *before* this status lands, because its trigger is
	# "another element's status" — one already on the target. Reading it after the
	# write would make every application its own trigger. The firing happens after
	# the write, once the applied status is fully in place (G24).
	var combo_kind: int = _combo_for(status)
	# "consumes the listed stacks" is the same past tense as the trigger: the
	# stacks the row names are the ones the target *already had*, so SHATTER spends
	# the Chill/Freeze that was there. A Frost application on a burning target
	# therefore bursts with nothing to spend and leaves the Chill it brought for the
	# next Fire hit to shatter. Read here, with the table, for the same reason — this
	# status has not landed yet.
	var combo_frost: int = stacks(Status.CHILL) + stacks(Status.FREEZE)
	# SPEC-stats-status's closing paragraph: a boss at 0.0 resistance has Freeze
	# "downgraded to Chill", so the freeze never lands as one. Checked before the
	# entry is touched: the application is transformed, not refused, and what
	# lands is announced as the Chill it becomes.
	if status == Status.FREEZE and degrades_freeze():
		return _heavy_chill(source)
	var entry: Dictionary = _entry(status)
	var total: int = int(entry["stacks"]) + stacks
	var cap: int = max_stacks(status)
	if cap != UNLIMITED_STACKS:
		total = mini(total, cap)
	# SPEC-stats-status, CHILL's row: "At 5 converts to `FREEZE`" — the 5th stack
	# is never held as Chill. Only an entity that may hold FREEZE converts: a
	# player is one of the three statuses FREEZE is forbidden to, so a player
	# simply sits at the Chill cap (the spec's own last line, applied here rather
	# than left for the caller). A fully resistant entity does not convert either
	# — that conversion is the one way a freeze could still reach it, undoing the
	# downgrade above — so its Chill simply sits at the cap, slowed the whole way.
	if status == Status.CHILL and total >= CHILL_MAX_STACKS and allows(Status.FREEZE) \
			and not degrades_freeze():
		return _freeze_from_chill(source)
	entry["stacks"] = total
	entry["remaining"] = resisted_duration(status)
	entry["source"] = source if is_instance_valid(source) else null
	if status == Status.FREEZE:
		_freeze_double_ready = true
	_sync_speed_modifiers(status)
	status_applied.emit(status, total)
	Events.status_applied.emit(entity(), status, total, source)
	if status == Status.SHOCK:
		_chain_shock(source, trigger_damage)
	_maybe_trigger_combo(combo_kind, status, source, trigger_damage, combo_frost)
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


## Removes every active status, announcing each as it goes, and drops the combos
## those statuses triggered: a reaction's lasting effect (HEMORRHAGE's crit
## window, SUPERCONDUCT's Defense penalty) belongs to the statuses that produced
## it, so clearing them must not leave one running.
func clear_all() -> void:
	var present: Array[int] = _active.keys()
	for status: int in present:
		clear(status)
	clear_combos()


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
## row, "+10 % all damage taken per stack". 1.0 with no UNRAVEL. Read into the
## formula's `status_mult` term by `incoming_damage_multiplier()` below, which is
## what `Damage.compute` actually calls: this is the target-side part of it.
func damage_taken_multiplier() -> float:
	return 1.0 + UNRAVEL_DAMAGE_TAKEN_PER_STACK * float(stacks(Status.UNRAVEL))


# --- G23: the resistance field and the formula's whole status term ------------

## The whole `status_mult` term of SPEC-stats-status's formula, in one place so
## its three parts cannot be dropped, reordered or counted twice:
##
##   `status_mult = 1.0 (+0.25 Kindling on BURN) (+1.0 Permafrost on FREEZE,
##                      once) (+UNRAVEL stacks * 0.1)`
##
## `attacker_host` is the *attacking* entity's `EffectHost`, which is where the
## two attacker-side terms are read from — `Damage.compute` looks it up on the
## attacker's parent and passes it in. Passing none (a hazard, a status tick, a
## fixture) leaves the relic terms at zero rather than guessing. The entity's own
## host is consulted as well, through `has_relic()`'s usual rule, so a status an
## entity applied to itself reads the same relic.
##
## **Side effect, by design:** the FREEZE term is the *pending* freeze double, so
## reading this spends it — the spec's "once", and the reason the second hit on a
## frozen target is a normal one. Permafrost is what makes the bonus land on
## every hit instead; it still spends the double, so the one-shot cannot be
## banked and cashed by a later attacker who has neither relic.
func incoming_damage_multiplier(attacker_host: EffectHost = null) -> float:
	var multiplier: float = damage_taken_multiplier()
	if has(Status.BURN) and _attacker_holds(KINDLING_ID, attacker_host):
		multiplier += KINDLING_BURN_BONUS
	multiplier += _freeze_damage_bonus(attacker_host)
	return multiplier


## The formula's FREEZE term, "+1.0 Permafrost on FREEZE, once": +1.0 while the
## pending double is unspent, and +1.0 on every hit while Permafrost is held.
## Zero for a target that is not frozen at all — the double belongs to a freeze,
## it is not a charge the entity banks for later.
func _freeze_damage_bonus(attacker_host: EffectHost) -> float:
	if not has(Status.FREEZE):
		return 0.0
	var permafrost := _attacker_holds(PERMAFROST_ID, attacker_host)
	var pending := consume_freeze_double()
	return FREEZE_DAMAGE_BONUS if permafrost or pending else 0.0


## Whether the attacking side holds relic `id`: the host `Damage.compute` read
## off the attacker, or this entity's own host when the entity applied the status
## to itself — the same either-side rule `has_relic()` already applies to an
## applier's relic, in one place so two readers of the same relic cannot drift.
func _attacker_holds(id: StringName, attacker_host: EffectHost) -> bool:
	if attacker_host != null and is_instance_valid(attacker_host) and attacker_host.has_effect(id):
		return true
	return has_relic(id)


## The scaled seconds `status` runs for on this entity: the table's duration
## multiplied by `status_resistance`. 1.0 reads as the table's own number, and
## above 1.0 lengthens the status — it is a multiplier, not a cap. 0.0 leaves no
## clock at all, which the next frame's tick expires; FREEZE is the one row with
## a clause for that ("Freeze becomes heavy Chill") and is downgraded before it
## ever reaches this. MARK's `NO_EXPIRY` 0.0 stays 0.0 whatever the resistance,
## i.e. still no expiry.
func resisted_duration(status: Status) -> float:
	return duration(status) * status_resistance


## Whether FREEZE is downgraded on this entity: SPEC-stats-status's closing
## paragraph, "Freeze becomes heavy Chill", at or below `NO_STATUS_RESISTANCE`.
## Read by `apply_status()` — which sends the application to `_heavy_chill()`
## instead of holding a freeze — and by the Chill cap's conversion, which is the
## one other route to a freeze and is therefore held back for the same reason.
func degrades_freeze() -> bool:
	return status_resistance <= NO_STATUS_RESISTANCE


## Lands a refused-by-resistance FREEZE as heavy Chill: the Chill cap's stacks,
## the entity's own Chill clock, and the slow that comes with them. Announced as
## the Chill it is, so a HUD icon and an effect listening on
## `Events.status_applied` see what the entity actually received.
##
## The duration is the Chill table's own, deliberately *not* passed through
## `resisted_duration()`: the spec's clause is "Freeze becomes heavy Chill rather
## than *doing nothing*", and multiplying the downgrade by the same 0.0 that
## triggered it would be exactly the doing-nothing it exists to avoid.
##
## Called only from `apply_status()`, for an entity `degrades_freeze()` is true
## for; never for an entity that may hold FREEZE, which holds the real thing.
func _heavy_chill(source: Node) -> bool:
	clear(Status.CHILL)
	var entry: Dictionary = _entry(Status.CHILL)
	entry["stacks"] = HEAVY_CHILL_STACKS
	entry["remaining"] = duration(Status.CHILL)
	entry["source"] = source if is_instance_valid(source) else null
	_sync_speed_modifiers(Status.CHILL)
	status_applied.emit(Status.CHILL, HEAVY_CHILL_STACKS)
	Events.status_applied.emit(entity(), Status.CHILL, HEAVY_CHILL_STACKS, source)
	return true


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
func chain_hit(amount: int) -> HitInfo:
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


# --- the six element combos (G24) --------------------------------------------
#
# SPEC-stats-status, "Element combos". `_combo_for()` reads the table, and it is
# read *before* the application lands (see `apply_status()`), because every
# trigger names an element the target already had — and "consumes the listed
# stacks" is the same past tense, so what a row spends is the stacks that were
# there, not the status this application is landing. `_maybe_trigger_combo()`
# then fires it once and emits through the bus.
# Two rows need the world and both are requests, not effects: CONDUCT's spread
# asks the connected-water-area seam and COLLAPSE's pull asks the enemy body —
# neither provider exists yet (Dev A's), so a case asserts the request.

## The combo `applied` triggers on this entity, as a `Combo.Kind`, or `NO_COMBO`
## when the application is not a reaction.
##
## The rules are the table's own rows, read in the table's order so that a target
## carrying two eligible elements fires exactly one combo — the spec's "the combo
## fires once", with the tie broken deterministically rather than by dictionary
## order. "No combo when same element reapplied" falls out of the pair rules:
## every one of them names a different element on each side, so Fire on Fire, a
## second Chill and the rest of the re-applies match nothing.
func _combo_for(applied: Status) -> int:
	var element: int = STATUS_ELEMENT.get(applied, HitInfo.Element.NONE)
	if element == HitInfo.Element.NONE:
		return NO_COMBO
	var frost: bool = _has_element(HitInfo.Element.FROST, applied)
	var fire: bool = _has_element(HitInfo.Element.FIRE, applied)
	var storm: bool = _has_element(HitInfo.Element.STORM, applied)
	if element == HitInfo.Element.FIRE and frost:
		return Combo.Kind.SHATTER
	if element == HitInfo.Element.FROST and fire:
		return Combo.Kind.SHATTER
	if element == HitInfo.Element.STORM and is_wet():
		return Combo.Kind.CONDUCT
	if element == HitInfo.Element.FIRE and has(Status.TOXIN):
		return Combo.Kind.BLIGHT_EXPLOSION
	if element == HitInfo.Element.SHADOW and has(Status.BLEED):
		return Combo.Kind.HEMORRHAGE
	if element == HitInfo.Element.FROST and storm:
		return Combo.Kind.SUPERCONDUCT
	if element == HitInfo.Element.STORM and frost:
		return Combo.Kind.SUPERCONDUCT
	if element == HitInfo.Element.VOID and _has_other_element(applied):
		return Combo.Kind.COLLAPSE
	return NO_COMBO


## Whether the entity holds a status of `element` other than `applied` — the
## "another element's status" half of every pair rule. CHECKED so CHILL and
## FREEZE are one element: a Fire application shatters either.
func _has_element(element: int, applied: Status) -> bool:
	for status: int in _active.keys():
		if status == applied:
			continue
		if int(STATUS_ELEMENT.get(status, HitInfo.Element.NONE)) == element:
			return true
	return false


## Whether the entity holds any status whose element differs from `applied`'s —
## COLLAPSE's "Void on any other status".
func _has_other_element(applied: Status) -> bool:
	var element: int = STATUS_ELEMENT.get(applied, HitInfo.Element.NONE)
	for status: int in _active.keys():
		if status == applied:
			continue
		if int(STATUS_ELEMENT.get(status, HitInfo.Element.NONE)) != element:
			return true
	return false


## Fires `combo_kind` if the pass above found one: builds the payload, applies
## the row's own lasting effect or consume, scales the row's damage by the two
## consumer hooks, and emits `Events.combo_triggered` **once**. A no-op — and a
## `false` — when `combo_kind` is `NO_COMBO`, so the caller needs no second
## branch.
##
## The body is two passes over the same row: the first settles everything that
## does not depend on the multiplier (which stacks are consumed, which window is
## armed, how much damage the row's own arithmetic produces), the multiplier is
## applied **once** between them, and the second delivers what it settled. That
## is deliberately the only place a combo's damage is scaled, so a row added
## later cannot be silently left out of the multiplication the way a third
## delivery branch would.
##
## `existing_frost` is the Chill + Freeze stacks the target held *before* this
## application, which is what SHATTER's "consumes Chill/Freeze" spends; every
## other row's consume names a status the trigger already required to be present,
## so it reads it here (Toxin for BLIGHT_EXPLOSION) or names none at all.
func _maybe_trigger_combo(combo_kind: int, applied: Status, source: Node, trigger_damage: int, existing_frost: int = 0) -> bool:
	if combo_kind == NO_COMBO:
		return false
	var element: int = STATUS_ELEMENT.get(applied, HitInfo.Element.NONE)
	var combo := Combo.new(combo_kind)
	match combo_kind:
		Combo.Kind.SHATTER:
			# "Burst 200% of trigger damage in 64 px, consumes Chill/Freeze." The
			# frost the target already held is what goes — both statuses of it, so a
			# frozen-and-chilled target is left with neither — and the application
			# that fired the combo still lands.
			combo.damage = roundi(float(maxi(trigger_damage, 0)) * SHATTER_BURST_FRACTION)
			combo.radius = SHATTER_RADIUS
			combo.stacks = existing_frost
			if existing_frost > 0:
				clear(Status.CHILL)
				clear(Status.FREEZE)
		Combo.Kind.CONDUCT:
			# "Shock spreads to every enemy touching the connected water area."
			# The row names no number of its own, so the spread carries the shock
			# chain's own damage — 30 % of the trigger damage, SHOCK's row.
			combo.damage = chain_damage(trigger_damage)
			combo.radius = SHOCK_CHAIN_RADIUS
		Combo.Kind.BLIGHT_EXPLOSION:
			# "Explosion 40% per Toxin stack, consumes Toxin." All the stacks go.
			combo.stacks = stacks(Status.TOXIN)
			combo.damage = roundi(BLIGHT_PER_STACK * float(combo.stacks) * float(maxi(trigger_damage, 0)))
			clear(Status.TOXIN)
		Combo.Kind.HEMORRHAGE:
			# "Bleed ticks crit for 4 s." Nothing is consumed: the row lists no
			# stacks, and the Bleed is the thing that keeps ticking.
			combo.duration = HEMORRHAGE_SECONDS
			_combo_remaining[Combo.Kind.HEMORRHAGE] = HEMORRHAGE_SECONDS
		Combo.Kind.SUPERCONDUCT:
			combo.duration = SUPERCONDUCT_SECONDS
			_combo_remaining[Combo.Kind.SUPERCONDUCT] = SUPERCONDUCT_SECONDS
			_apply_superconduct()
		Combo.Kind.COLLAPSE:
			combo.radius = COLLAPSE_RADIUS
		_:
			pass
	# The spec's last line, "Reactive skill node (+40%) and Elementalist synergy
	# (x2) multiply combo damage", in one place: a row that deals no damage stays
	# at 0, and every row that does carries what its two consumers made of it.
	combo.damage = scaled_combo_damage(combo.damage, source)
	match combo_kind:
		Combo.Kind.SHATTER:
			if combo.damage > 0:
				for target: Node in _combo_targets(SHATTER_RADIUS):
					_deliver_to(target, combo_hit(combo, element))
		Combo.Kind.CONDUCT:
			if combo.damage > 0:
				_spread_conduct(combo, element)
		Combo.Kind.BLIGHT_EXPLOSION:
			if combo.damage > 0:
				_deliver_to(entity(), combo_hit(combo, element))
		Combo.Kind.COLLAPSE:
			# The pull depends on no damage, so it is independent of what the
			# consumers did to the row's number.
			_request_pull()
		_:
			pass
	Events.combo_triggered.emit(entity(), combo, source)
	return true


## A combo's damage after the two consumer hooks have had their say:
## `Scaling`-shaped arithmetic with the spec's sentence behind it, kept as one
## function so the multiplication happens in exactly one place. A row that deals
## no damage stays at 0 — the multiplier is a multiplier, not a floor.
func scaled_combo_damage(raw: int, source: Node) -> int:
	if raw <= 0:
		return 0
	return roundi(float(raw) * combo_damage_multiplier(source))


## The multiplier every combo's damage is scaled by, from SPEC-stats-status's
## last sentence about the table: "Reactive skill node (+40%) and Elementalist
## synergy (x2) multiply combo damage."
##
## Read off the **applying** entity's effects, and never off an id: each effect
## attached to the applier's `EffectHost` that exposes `COMBO_MULTIPLIER_METHOD`
## contributes a factor, and the factors compose multiplicatively. Nothing
## contributing is `COMBO_DAMAGE_BASE` — exactly 1.0, which is the spec's own
## case for a build holding neither system.
##
## `source` is the effect that applied the status, i.e. what `apply_status()` was
## handed; a source that is not an `Effect`, or one whose host is gone, is the
## base. The **target's** own host deliberately does not contribute: the
## multiplier belongs to whoever dealt the hit, and reading the target's would let
## an enemy's relics scale the damage dealt to it.
##
## Host-side, like every other combo path: a combo only fires where
## `_resolves_statuses()` is true, so a client never reads this. Where the real
## consumers attach: the Elementalist synergy (week 8, `SynergyTracker`) and the
## Reactive skill node (week 7, progression-trees) each attach an `Effect`
## exposing this method to the player's `EffectHost`; until they exist,
## `tests/helpers/combo_consumer_stub.gd` stands in for both.
func combo_damage_multiplier(source: Node) -> float:
	var applying := source as Effect
	if applying == null or not is_instance_valid(applying.host):
		return COMBO_DAMAGE_BASE
	var multiplier: float = COMBO_DAMAGE_BASE
	for effect: Effect in applying.host.effects():
		if effect.has_method(COMBO_MULTIPLIER_METHOD):
			multiplier *= _combo_factor(effect)
	return multiplier


## One consumer's factor, read through the hook. A consumer that returns
## something which is not a number contributes nothing, and a negative factor is
## floored at zero, so a malformed consumer can neither break a reaction nor flip
## the sign of its damage.
func _combo_factor(effect: Effect) -> float:
	var value: Variant = effect.call(COMBO_MULTIPLIER_METHOD)
	if not (value is float or value is int):
		return COMBO_DAMAGE_BASE
	return maxf(float(value), 0.0)


## Whether the entity counts as `wet` for CONDUCT. Read off the entity's
## `WET_PROPERTY` when it carries one, and false otherwise — a dry entity, one
## with no water tile, and every fixture that has not declared the property
## (**blocked on Dev A (W4-A1)** for the real tile / `Drowned` enemy).
func is_wet() -> bool:
	var owner_entity := entity()
	if owner_entity == null:
		return false
	var value: Variant = owner_entity.get(WET_PROPERTY)
	return value is bool and bool(value)


## The enemies touching this entity's connected water area, via the
## `WATER_AREA_METHOD` seam. Empty for an entity that carries no such query —
## which is every entity today (**blocked on Dev A (W2-A1, water tiles)**), so
## CONDUCT's spread is a request the case asserts rather than a spread that
## happened.
func connected_water_targets() -> Array[Node]:
	var found: Array[Node] = []
	var owner_entity := entity()
	if owner_entity == null or not owner_entity.has_method(WATER_AREA_METHOD):
		return found
	var result: Variant = owner_entity.call(WATER_AREA_METHOD)
	if not (result is Array):
		return found
	var listing: Array = result
	for node: Variant in listing:
		if node is Node and is_instance_valid(node):
			found.append(node as Node)
	return found


## Runs CONDUCT's spread: the combo's damage to every enemy the water-area seam
## returned.
func _spread_conduct(combo: Combo, element: int) -> void:
	for target: Node in connected_water_targets():
		if target == entity():
			continue
		_deliver_to(target, combo_hit(combo, element))


## Lands SUPERCONDUCT's "-30% Defense": one percent modifier under
## `SUPERCONDUCT_SOURCE`, removed and re-added so a second reaction refreshes the
## penalty instead of stacking it. `base` is never written (SPEC-project).
func _apply_superconduct() -> void:
	var block := stat_block()
	if block == null:
		return
	block.remove_source(SUPERCONDUCT_SOURCE)
	block.add_modifier(StatBlock.Stat.DEFENSE, 0.0, SUPERCONDUCT_DEFENSE, SUPERCONDUCT_SOURCE)


## Asks every enemy within `COLLAPSE_RADIUS` of the target to pull toward it,
## through the `PULL_METHOD` seam. The target itself is the centre of the pull,
## not one of its subjects, and an enemy with no such method is skipped — the
## movement is Dev A's enemy body (**blocked on Dev A (W4-A1)**), which is why
## this is a request and not a position change.
func _request_pull() -> void:
	for target: Node in _combo_targets(COLLAPSE_RADIUS):
		if target == entity() or not is_instance_valid(target):
			continue
		if target.has_method(PULL_METHOD):
			target.call(PULL_METHOD, entity(), COLLAPSE_RADIUS)


## The nodes a burst reaches: the entity itself plus every `ENEMY_TAG` node
## within `radius` — SHATTER's "in 64 px" and COLLAPSE's "within 128 px", one
## measurement rather than two. The candidate set is the group Dev A's enemies
## register in (**blocked on Dev A (W4-A1)**; today it is whatever the world or a
## double put there), and the entity is included unconditionally so a burst
## centred on it can land on it (a target with no `Health` is skipped by the
## delivery, silently).
func _combo_targets(radius: float) -> Array[Node]:
	var found: Array[Node] = []
	var tree := get_tree()
	if tree != null:
		var here := _entity_position()
		for candidate: Node in tree.get_nodes_in_group(ENEMY_TAG):
			if candidate == entity() or not is_instance_valid(candidate):
				continue
			var positioned := candidate as Node2D
			if positioned == null:
				continue
			if here.distance_to(positioned.global_position) <= radius:
				found.append(candidate)
	found.append(entity())
	return found


## Whether Bleed ticks crit right now: true while a HEMORRHAGE window is open
## ("Bleed ticks crit for 4 s"). Read by `_tick()`, which doubles the tick's hit.
func bleed_ticks_crit() -> bool:
	return _combo_remaining.has(Combo.Kind.HEMORRHAGE)


## Whether a combo's lasting effect is running, and how long it has left, in
## scaled seconds. The two rows with a duration are the only ones that can be
## active; every other combo is finished the moment it fires.
func combo_active(kind: int) -> bool:
	return _combo_remaining.has(kind)


func combo_remaining(kind: int) -> float:
	return float(_combo_remaining.get(kind, 0.0))


## Drops every combo's lasting effect, releasing what it holds (SUPERCONDUCT's
## Defense modifier) as it goes. Called by `clear_all()` and by a caller that
## resets an entity — the counterpart of `clear()` for the reaction layer.
func clear_combos() -> void:
	var active: Array[int] = _combo_remaining.keys()
	for kind: int in active:
		_expire_combo(kind)


## The `HitInfo` a combo's own damage travels as: the amount as both
## `base_damage` and `final_damage` (the combo's damage is an outcome, not a
## formula input, so it bypasses `Damage.compute`), the triggering element, and
## the `COMBO_TAG` plus the combo's own name. No proc depth and no crit roll: a
## reaction is the target's event, not a chain link of the attacker's effects.
func combo_hit(combo: Combo, element: int) -> HitInfo:
	var hit := HitInfo.new()
	hit.base_damage = float(combo.damage)
	hit.final_damage = combo.damage
	hit.element = element
	hit.tags = [COMBO_TAG, combo.name()]
	return hit


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
func deal_status_damage(status: Status, amount: int, is_crit: bool = false) -> bool:
	if amount <= 0:
		return false
	if health_of(entity()) == null:
		if not _warned_missing_health:
			_warned_missing_health = true
			push_warning("[status] %s: no %s to receive status damage, ticks dropped" % [
				entity_name(), HEALTH_NODE])
		return false
	return _deliver_to(entity(), tick_hit(status, amount, is_crit))


## The `HitInfo` a tick hands over: the amount as both `base_damage` and
## `final_damage` (so whichever of the two the real `Health` reads, the number
## is the tick's), the status's element, and the `status` tag plus the status's
## own name. No proc depth: a tick is not a chain link of effects.
##
## `is_crit` is set only for a Bleed tick inside a HEMORRHAGE window ("Bleed
## ticks crit for 4 s"), and it is the *doubling* as well as the flag — a tick
## bypasses `Damage.compute`, so there is no roll and no `CRIT_DAMAGE` to read,
## and `COMBO_CRIT_MULTIPLIER` is the whole of it. Every other tick is not a
## crit and cannot be.
func tick_hit(status: Status, amount: int, is_crit: bool = false) -> HitInfo:
	var hit := HitInfo.new()
	hit.base_damage = float(amount)
	hit.final_damage = roundi(float(amount) * COMBO_CRIT_MULTIPLIER) if is_crit else amount
	hit.is_crit = is_crit
	hit.element = STATUS_ELEMENT.get(status, HitInfo.Element.NONE)
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
func _deliver_to(target: Node, hit: HitInfo) -> bool:
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
	if _active.is_empty() and _combo_remaining.is_empty():
		return
	if not _resolves_statuses():
		return
	var scale := TimeManager.scale_for(entity())
	if scale <= 0.0:
		return
	# The combos' own clocks are scaled the same way, and run even when the
	# target carries no status any more: SUPERCONDUCT's penalty outlives the
	# Shock and Chill that produced it.
	_tick_combos(delta * scale)
	if _active.is_empty():
		return
	_tick(delta * scale)


## Counts the combos' lasting effects down and releases what an expired one
## holds. Only the rows with a duration are ever keys.
func _tick_combos(scaled_delta: float) -> void:
	if _combo_remaining.is_empty():
		return
	var expired: Array[int] = []
	for kind: int in _combo_remaining.keys():
		var left: float = maxf(float(_combo_remaining[kind]) - scaled_delta, 0.0)
		_combo_remaining[kind] = left
		if left <= 0.0:
			expired.append(kind)
	for kind: int in expired:
		_expire_combo(kind)


## Ends one combo's lasting effect and takes back what it holds. The only thing
## a combo leaves on the entity today is SUPERCONDUCT's Defense modifier, and it
## is released under its own source, so the entity's other modifiers survive.
func _expire_combo(kind: int) -> void:
	_combo_remaining.erase(kind)
	if kind != Combo.Kind.SUPERCONDUCT:
		return
	var block := stat_block()
	if block != null:
		block.remove_source(SUPERCONDUCT_SOURCE)


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
			deal_status_damage(status, whole, status == Status.BLEED and bleed_ticks_crit())
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
## slow) and the freeze is applied on top, carrying its (resisted) duration and
## arming the one-shot double. Announced like any other application, so a HUD icon
## and an effect listening on `Events.status_applied` see the freeze rather than a
## Chill that never existed.
##
## Called only from `apply_status()`, after both gates have already decided this
## entity may hold FREEZE: it is not a player, and its `status_resistance` does
## not `degrades_freeze()`.
func _freeze_from_chill(source: Node) -> bool:
	clear(Status.CHILL)
	var entry: Dictionary = _entry(Status.FREEZE)
	entry["stacks"] = FREEZE_MAX_STACKS
	entry["remaining"] = resisted_duration(Status.FREEZE)
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