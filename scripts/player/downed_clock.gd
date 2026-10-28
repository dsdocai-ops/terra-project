class_name DownedClock
extends RefCounted
## The pure downed numbers and the bleed-out / revive-hold bookkeeping behind
## the Downed and Dead states (SPEC-player-controller "Downed and revive",
## W3-A5's logic half). Owned by player-controller; the Player — and, once they
## land, its Downed and Dead states — steps it and reads it. Sync: none inside.
## The bleed-out and the hold are host decisions (damage and revive run on the
## host), so the clock runs on the host; the resulting is_downed / is_dead
## flags replicate through StateSync as they already do.
##
## No tree, no physics, no StatBlock inside: the caller passes the
## revive_speed_mult in, so a test can drive every number without a scene
## (the DodgeClock pattern).

## Bleed-out window after a co-op down (SPEC: "shows a bleed-out timer of
## 30 s"). Player.BLEED_OUT_SECONDS holds the same number for the scene.
const BLEED_OUT_SECONDS: float = 30.0
## Teammates hold interact for 3 s to revive (SPEC). NetworkManager.REVIVE_SECONDS
## holds the same number for the host's revive path.
const REVIVE_HOLD_SECONDS: float = 3.0
## The revived player comes back at 40% HP (SPEC). NetworkManager.REVIVE_HP_FRACTION
## applies it; the constants cannot drift while the tests compare them.
const REVIVE_HP_FRACTION: float = 0.4
## Smallest revive_speed_mult a hold may be scaled by — the mirror of
## NetworkManager.REVIVE_SPEED_MULT_MIN, so a zeroed or negative modifier
## cannot stretch the hold to infinity.
const MIN_SPEED_MULT: float = 0.1

## Seconds of bleed-out left. 0.0 while the player is not down.
var bleed_out_left: float = 0.0
## Seconds the running revive hold has banked.
var hold_banked: float = 0.0
## The length the running hold uses. 0.0 when no hold is running, so the hold
## never advances before `begin_hold`.
var hold_seconds: float = 0.0


## SPEC: "Solo: downed is skipped, Dead immediately." Solo means no teammate
## is standing; the same rule the Player's `_teammate_standing()` decides.
static func goes_straight_to_dead(teammates_standing: bool) -> bool:
	return not teammates_standing


## The hold a reviver with this multiplier takes: 3 s divided by the mult
## (Field Medic twice as fast is half the hold), floored at MIN_SPEED_MULT.
func hold_duration(speed_mult: float) -> float:
	return REVIVE_HOLD_SECONDS / maxf(speed_mult, MIN_SPEED_MULT)


## Starts the 30 s bleed-out clock.
func start_bleed_out() -> void:
	bleed_out_left = BLEED_OUT_SECONDS


## True while bleed-out is still counting. A player that is not down has
## `bleed_out_left` at 0.0 and reads false.
func bleeding() -> bool:
	return bleed_out_left > 0.0


## Revive or death stops the clock before it expires.
func stop_bleed_out() -> void:
	bleed_out_left = 0.0


## A reviver starts holding: the hold runs the reviver's scaled duration and
## banks from zero. (Called again mid-hold it restarts the attempt — the
## caller decides when a hold is live.)
func begin_hold(speed_mult: float) -> void:
	hold_seconds = hold_duration(speed_mult)
	hold_banked = 0.0


## True while a reviver holds. The hold only advances a clock between
## `begin_hold` and `break_hold`.
func holding() -> bool:
	return hold_seconds > 0.0


## The reviver let go or walked out of range. A hold is a continuous hold:
## nothing banks, and the next attempt starts from zero.
func break_hold() -> void:
	hold_seconds = 0.0
	hold_banked = 0.0


## Hold progress, 0.0 to 1.0, of the running hold. Without a running hold:
## 0.0.
func hold_progress() -> float:
	if hold_seconds <= 0.0:
		return 0.0
	return clampf(hold_banked / hold_seconds, 0.0, 1.0)


## The reviver has held the full duration: the revive may apply.
func hold_complete() -> bool:
	return holding() and hold_banked >= hold_seconds


## Steps the bleed-out down and the hold bank up. The caller passes the delta
## already scaled however its clock runs (the host counts real seconds; a
## TimeManager slow is a gameplay decision the caller owns). The bleed-out
## stops at 0.0 and never goes negative; the hold stops at its duration and
## never overshoots.
func tick(delta: float) -> void:
	if bleeding():
		bleed_out_left = maxf(bleed_out_left - delta, 0.0)
	if holding() and hold_banked < hold_seconds:
		hold_banked = minf(hold_banked + delta, hold_seconds)


## Back to fresh-run state: nothing bleeding, no hold running.
func reset() -> void:
	bleed_out_left = 0.0
	hold_seconds = 0.0
	hold_banked = 0.0
