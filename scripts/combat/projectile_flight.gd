class_name ProjectileFlight
extends RefCounted
## Pure flight math for the `Projectile` base (W2-A6): homing turn rate, wall
## bounce count and angle, lifetime and range budgets, the reflect flag, and
## time-scaled stepping. Owned by combat-core.
## Sync: none — host-only numbers; the pose they produce replicates through
## `Projectile.synced_position` / `synced_velocity`. The owning node reads the
## bounce count from its `ProjectileSpec` and hands the budgets over at launch;
## nothing here touches the tree, physics or `TimeManager` (the caller passes
## `TimeManager.scale_for(node)` in).

## Seconds of flight left when the projectile carries no lifetime limit.
const NO_LIFETIME: float = 0.0

## Pixels per second; the node sets this from its spawn velocity.
var velocity: Vector2 = Vector2.ZERO
## Radians per second the projectile may turn toward its homing target.
## 0.0 flies dead straight (SPEC-combat-core `homing_strength`).
var homing_strength: float = 0.0
## Ricochets remaining off walls. 0 dies on the first wall (the old behaviour).
var bounces_left: int = 0
## Whether a reflect source (Guardian block, Crystal Hollows crystal) can send
## the projectile back the way it came (SPEC-combat-core `reflectable`).
var reflectable: bool = false
## Pixels of flight remaining before the projectile expires.
var distance_left: float = 0.0
## Seconds of flight remaining; `NO_LIFETIME` means unlimited.
var lifetime_seconds: float = NO_LIFETIME
var _lifetime_left: float = NO_LIFETIME


## Arms the lifetime budget. Called by the owner once, at launch.
func arm(p_velocity: Vector2, p_distance: float, p_lifetime: float) -> void:
	velocity = p_velocity
	distance_left = p_distance
	lifetime_seconds = maxf(p_lifetime, NO_LIFETIME)
	_lifetime_left = lifetime_seconds


## Turns the velocity toward `target_position` seen from `origin`, by at most
## the homing turn rate for this frame (`delta` seconds at `time_scale`).
## Returns the angle turned (>= 0). Never overshoots: a frame whose budget
## exceeds the remaining angle points the velocity exactly at the target. A
## projectile without homing strength, or with no velocity to turn, stays put.
func turn_toward(target_position: Vector2, origin: Vector2, delta: float, time_scale: float = 1.0) -> float:
	if homing_strength <= 0.0 or velocity == Vector2.ZERO:
		return 0.0
	var to_target: Vector2 = target_position - origin
	if to_target == Vector2.ZERO:
		return 0.0
	var wanted: float = to_target.angle()
	var current: float = velocity.angle()
	var difference: float = wrapf(wanted - current, -PI, PI)
	var max_turn: float = homing_strength * maxf(delta, 0.0) * maxf(time_scale, 0.0)
	var turn: float = clampf(difference, -max_turn, max_turn)
	velocity = velocity.rotated(turn)
	return absf(turn)


## Reflects the velocity off a wall whose surface normal is `normal` and
## consumes one bounce. Returns false — and changes nothing — when no bounce
## is left, which is the caller's signal to stop the projectile.
func bounce_off(normal: Vector2) -> bool:
	if bounces_left <= 0:
		return false
	bounces_left -= 1
	# Mirror the velocity's component along the normal: the classic
	# reflection `v - 2 (v . n) n`, spelled out so the angle never depends
	# on the caller passing a normalized `normal` in the right form.
	velocity = velocity - 2.0 * velocity.dot(normal) * normal
	return true


## A reflect source bats the projectile back the way it came (or, with a
## surface normal, mirrors it off that surface). Returns false — and changes
## nothing — when the projectile is not reflectable.
func reflect(surface_normal: Vector2 = Vector2.ZERO) -> bool:
	if not reflectable:
		return false
	if surface_normal == Vector2.ZERO:
		velocity = -velocity
	else:
		velocity = velocity - 2.0 * velocity.dot(surface_normal) * surface_normal
	return true


## One frame of flight at `time_scale`: returns the displacement to apply.
## Burns the distance budget by the step length and the lifetime budget by the
## scaled seconds, so a frozen projectile (scale 0) neither moves nor expires.
func advance(delta: float, time_scale: float = 1.0) -> Vector2:
	var scaled: float = maxf(delta, 0.0) * maxf(time_scale, 0.0)
	var step: Vector2 = velocity * scaled
	if step == Vector2.ZERO:
		return step
	distance_left -= step.length()
	if lifetime_seconds > NO_LIFETIME:
		_lifetime_left = maxf(_lifetime_left - scaled, 0.0)
	return step


## Whether the flight is over: the range ran out, or a configured lifetime did.
func is_expired() -> bool:
	if distance_left <= 0.0:
		return true
	if lifetime_seconds > NO_LIFETIME and _lifetime_left <= 0.0:
		return true
	return false
