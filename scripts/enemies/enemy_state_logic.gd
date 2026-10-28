class_name EnemyStateLogic
extends RefCounted
## Pure decision logic for the enemy standard states — Idle, Chase, HitStun,
## Stagger (SPEC-enemies-ai "Standard states"). Owned by enemies-ai. Sync:
## host-only; every caller runs on the host.
##
## Pure on purpose: every function sees plain values and returns plain values —
## no tree access, no physics, no clock of its own. The scene states under
## `scenes/enemies/states/` call these and apply the results (velocity,
## `move_and_slide`, `machine.change_to`), so the scene stays wiring and this
## file is the one source of the decisions. The Attack state's phase timing is
## the combat-core `AttackDriver` (`scripts/combat/attack_driver.gd`); the
## target choice is `Targeting` (`scripts/enemies/targeting.gd`). Movement is
## time-scaled by the caller: the state machine passes the TimeManager-scaled
## delta, and the enemy's own timers run on `TimeManager.scale_for(self)` —
## never `Engine.time_scale`.

## How often the Idle scan (targeting + aggro check) runs, in seconds.
const SCAN_SECONDS: float = 0.25
## How often the Chase state re-runs targeting, in seconds.
const RETARGET_SECONDS: float = 0.5
## A knockback impulse decays to nothing over this many seconds.
const KNOCKBACK_DECAY_SECONDS: float = 0.2
## Extra damage taken while staggered (combat v2 C2), as a factor.
const STAGGER_DAMAGE_TAKEN: float = 1.25
## Stagger length when the enemy has no data to read one from.
const DEFAULT_STAGGER_SECONDS: float = 0.8

## One timer step: `left` after `delta`, and whether the timer ran out this
## step (equal counts as out). The HitStun and Stagger clocks, the Idle scan
## and the Chase retarget all tick this way.
class TimerTick:
	var left: float = 0.0
	var over: bool = false


static func tick_down(left: float, delta: float) -> TimerTick:
	var tick := TimerTick.new()
	tick.left = left - delta
	tick.over = tick.left <= 0.0
	return tick


## True when a target at `dist` is close enough to aggro on (the Idle scan's
## check: equal counts as inside).
static func in_aggro(dist: float, aggro_range: float) -> bool:
	return dist <= aggro_range


## What the Chase state does about a target `dist` away, with `keep_distance`
## from the data: back away inside 0.8x the keep distance, hold inside it,
## close otherwise. A `keep_distance` of 0 (melee) always closes.
enum ChaseMove { BACK_OFF, HOLD, APPROACH }


static func chase_move(dist: float, keep_distance: float) -> ChaseMove:
	if keep_distance <= 0.0:
		return ChaseMove.APPROACH
	if dist < keep_distance * 0.8:
		return ChaseMove.BACK_OFF
	if dist <= keep_distance:
		return ChaseMove.HOLD
	return ChaseMove.APPROACH


## True when the Chase state should hand over to Attack: the pattern's trigger
## range met and the cooldown spent. The null-pattern check stays with the
## caller, which needs the pattern itself for the attack.
static func chase_attack(dist: float, trigger_range: float, cooldown_left: float) -> bool:
	return cooldown_left <= 0.0 and dist <= trigger_range


## The knockback velocity after one decay step: the impulse dies linearly over
## KNOCKBACK_DECAY_SECONDS.
static func decayed_knockback(velocity: Vector2, decel: float, delta: float) -> Vector2:
	return velocity.move_toward(Vector2.ZERO, decel * delta)


## The decel rate that kills an impulse of `impulse_speed` in
## KNOCKBACK_DECAY_SECONDS.
static func knockback_decel(impulse_speed: float) -> float:
	return impulse_speed / KNOCKBACK_DECAY_SECONDS if impulse_speed > 0.0 else 0.0


## A slide into a wall kills the knockback outright (the velocity the next
## frame starts from).
static func knockback_after_wall(velocity: Vector2, on_wall: bool) -> Vector2:
	return Vector2.ZERO if on_wall else velocity


## How long a poise break staggers: the data's `stagger_seconds`, or the
## default when the enemy has no data (`has_data` false).
static func stagger_length(has_data: bool, data_seconds: float) -> float:
	return data_seconds if has_data else DEFAULT_STAGGER_SECONDS
