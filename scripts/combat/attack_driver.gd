class_name AttackDriver
extends RefCounted
## The windup / active / recovery phase clock behind every `AttackPattern`
## (SPEC-combat-core "Enemy attack contract"). Owned by combat-core; the enemy
## state machine steps it each physics frame and reacts to its phase signals.
## Sync: host-only; clients replay the phases from the enemy's replicated
## `telegraph_progress` and `aim_dir`.
##
## The contract it enforces: **no hit without a telegraph.** The only way into
## ACTIVE is the windup boundary crossing inside `advance()`, and `may_hit()`
## also demands the telegraph ran to completion, so a driver that was stopped,
## reused or somehow poked into the ACTIVE phase still cannot arm a hit.
##
## `advance()` crosses at most one phase boundary per call and drops the time
## past it, so a hitch frame cannot run the whole attack inside one step: every
## phase change lands on its own physics frame and the active window is never
## entered and left in the same one. The caller hands in time already scaled
## (the state machine multiplies the delta by `effective_scale`), so time stops
## and slows hold the clock for free.

signal windup_started
signal active_started
signal recovery_started
signal attack_finished

enum Phase { WINDUP, ACTIVE, RECOVERY, DONE }

var pattern: AttackPattern = null

var _phase: Phase = Phase.DONE
var _elapsed: float = 0.0
## Set only when the windup boundary is crossed inside `advance()`. This is the
## telegraph gate: without it the phase alone proves nothing.
var _telegraph_done: bool = false


func phase() -> Phase:
	return _phase


## Starts a new attack on `new_pattern`: WINDUP from zero, telegraph disarmed.
func start(new_pattern: AttackPattern) -> void:
	pattern = new_pattern
	if pattern == null:
		stop()
		return
	_phase = Phase.WINDUP
	_elapsed = 0.0
	_telegraph_done = false
	windup_started.emit()


## Cancels the attack (a stagger, a state exit): nothing may hit afterwards.
func stop() -> void:
	_phase = Phase.DONE
	_elapsed = 0.0
	_telegraph_done = false


## Steps the clock by an already-scaled `delta` and returns the phase after the
## step. At most one boundary is crossed per call.
func advance(delta: float) -> Phase:
	if pattern == null or _phase == Phase.DONE:
		return _phase
	_elapsed += delta
	match _phase:
		Phase.WINDUP:
			if _elapsed >= pattern.windup_seconds:
				_telegraph_done = true
				_enter(Phase.ACTIVE, active_started)
		Phase.ACTIVE:
			if _elapsed >= pattern.active_seconds:
				_enter(Phase.RECOVERY, recovery_started)
		Phase.RECOVERY:
			if _elapsed >= pattern.recovery_seconds:
				_enter(Phase.DONE, attack_finished)
	return _phase


## The telegraph fill for the current step: 0..1 over the windup, -1 once the
## windup is over (the Telegraph hides itself on a negative).
func telegraph_progress() -> float:
	if pattern == null or _phase != Phase.WINDUP:
		return -1.0
	return clampf(_elapsed / maxf(pattern.windup_seconds, 0.01), 0.0, 1.0)


## The hit gate: true only while the active window runs AND the telegraph phase
## ran to completion first. A caller arms its hitbox or fires its projectile
## only behind this check.
func may_hit() -> bool:
	return _phase == Phase.ACTIVE and _telegraph_done


func _enter(next: Phase, signal_to_emit: Signal) -> void:
	_phase = next
	_elapsed = 0.0
	signal_to_emit.emit()
