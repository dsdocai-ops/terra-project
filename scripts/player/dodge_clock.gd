class_name DodgeClock
extends RefCounted
## The pure dodge numbers and the cooldown/charge bookkeeping behind the Dodge
## state (SPEC-player-controller "Dodge roll"). Owned by player-controller; the
## Player steps it in its combat-timer tick and the Dodge state reads its
## constants. Sync: none inside — the clock is host/owner-local state on the
## Player that runs the dodge, and the resulting movement replicates as
## position like the rest of the prediction.
##
## No tree, no physics, no StatBlock inside: the caller passes the
## DODGE_COOLDOWN stat value in, so a test can drive every number without a
## scene (the ProjectileFlight/AttackDriver pattern).

## Roll duration (SPEC "~0.25 s", tuned to 0.28 s on the Dodge state).
const DURATION_SECONDS: float = 0.28
## I-frames cover the whole roll (SPEC: "I-frames for the full roll").
const IFRAME_SECONDS: float = DURATION_SECONDS
## Roll speed as a multiple of move speed.
const SPEED_MULT: float = 2.6
## No modifier can push the recharge below this (Player's old floor).
const MIN_COOLDOWN_SECONDS: float = 0.1
## Charges without a synergy (SPEC: default 1, Phantom Dancer sets 2 — it
## raises `max_charges` on the clock, not the current count).
const DEFAULT_MAX_CHARGES: int = 1

## Spent charges recharge one per cooldown period, in order.
var max_charges: int = DEFAULT_MAX_CHARGES
var charges: int = DEFAULT_MAX_CHARGES
## Seconds left before the next charge refills. 0.0 when nothing is recharging.
var _cooldown_left: float = 0.0
## The length the running recharge uses; kept so a refill that still leaves a
## deficit restarts the tick at the same cost.
var _cooldown_seconds: float = 0.0


## The cooldown a dodge costs, from the StatBlock's DODGE_COOLDOWN value
## (base 0.8 s plus its modifiers), floored at MIN_COOLDOWN_SECONDS.
func cooldown_seconds(stat_value: float) -> float:
	return maxf(stat_value, MIN_COOLDOWN_SECONDS)


## True when a dodge can start: a charge is left. The cooldown gates the
## refill, not the spend — a second charge dodges while the first recharges.
func can_dodge() -> bool:
	return charges > 0


## Spends one charge and starts its recharge at `stat_value` seconds. Refused,
## and nothing changed, without a charge.
func spend(stat_value: float) -> bool:
	if charges <= 0:
		return false
	charges -= 1
	_cooldown_seconds = cooldown_seconds(stat_value)
	_cooldown_left = _cooldown_seconds
	return true


## Steps the recharge. Each completed cooldown refills one charge, up to max.
func tick(delta: float) -> void:
	if charges >= max_charges:
		return
	if _cooldown_left <= 0.0:
		# A deficit with no running recharge (a synergy just raised max).
		_cooldown_left = _cooldown_seconds
	_cooldown_left = maxf(_cooldown_left - delta, 0.0)
	if _cooldown_left <= 0.0:
		charges += 1
		if charges < max_charges:
			_cooldown_left = _cooldown_seconds


## Back to fresh-run state: full charges, no recharge running.
func reset() -> void:
	charges = max_charges
	_cooldown_left = 0.0
	_cooldown_seconds = 0.0


## The Kestrel hook (SPEC: "30% instant reset" calls reset_dodge_cooldown()).
## The running recharge finishes now — with the default single charge the next
## dodge is available immediately — and a still-missing charge starts its own
## recharge if more than one was spent.
func reset_dodge_cooldown() -> void:
	_cooldown_left = 0.0
	if charges < max_charges:
		charges += 1
		if charges < max_charges:
			_cooldown_left = _cooldown_seconds
