class_name CombatFeedbackConstants
extends RefCounted
## The one table of hit-stop, shake and flash tiers for every landed hit
## (combat-core, C1). Owned by combat-core. Sync: none, pure constants that are
## identical on all peers.
##
## `CombatFeedback` reads these to decide how hard a hit freezes time and shakes
## the camera. TimeManager.hit_stop freezes both entities in the exchange;
## GameCamera.shake is purely local.

## Hit-stop length in physics frames, by tier. A crit adds CRIT_BONUS_FRAMES on
## top of the base tier; a player hurt and a boss kill override everything.
const HIT_STOP_LIGHT_FRAMES: int = 3
const HIT_STOP_HEAVY_FRAMES: int = 6
const HIT_STOP_PLAYER_HURT_FRAMES: int = 4
const HIT_STOP_BOSS_KILL_FRAMES: int = 10
const HIT_STOP_CRIT_BONUS_FRAMES: int = 2
## A poise break (stagger) freezes longer than a heavy hit.
const HIT_STOP_STAGGER_FRAMES: int = 8

## Camera shake strength in px, by tier (GameCamera.shake). Light hits do not
## shake; a crit adds CRIT_BONUS_SHAKE on top of the base tier.
const SHAKE_NONE_PX: float = 0.0
const SHAKE_HEAVY_PX: float = 2.0
const SHAKE_PLAYER_HURT_PX: float = 3.0
const SHAKE_BOSS_KILL_PX: float = 8.0
const SHAKE_CRIT_BONUS_PX: float = 1.0
const SHAKE_STAGGER_PX: float = 4.0

## Duration of a shake impulse (seconds).
const SHAKE_SECONDS: float = 0.12

## Sprite flash length in physics frames (white, gold on a crit, red on a player).
const FLASH_FRAMES: int = 4
## A stagger flashes a little longer.
const FLASH_STAGGER_FRAMES: int = 6

## Damage number lives this far above the target's centre.
const NUMBER_LIFT_PX: float = 26.0


## Hit-stop frames for a landed hit. `is_heavy` covers both heavy attacks and
## finishers; a crit extends the tier by the bonus; a stagger uses its own tier; a
## hit on a player uses the player tier; a boss death overrides everything.
static func hit_stop_frames(is_heavy: bool, is_crit: bool, is_player_hurt: bool, is_boss_kill: bool, is_stagger: bool = false) -> int:
	if is_boss_kill:
		return HIT_STOP_BOSS_KILL_FRAMES
	if is_player_hurt:
		return HIT_STOP_PLAYER_HURT_FRAMES
	if is_stagger:
		return HIT_STOP_STAGGER_FRAMES
	var frames: int = HIT_STOP_HEAVY_FRAMES if is_heavy else HIT_STOP_LIGHT_FRAMES
	if is_crit:
		frames += HIT_STOP_CRIT_BONUS_FRAMES
	return frames


## Camera shake strength in px for a landed hit (local side only).
static func shake_px(is_heavy: bool, is_crit: bool, is_player_hurt: bool, is_boss_kill: bool, is_stagger: bool = false) -> float:
	if is_boss_kill:
		return SHAKE_BOSS_KILL_PX
	if is_player_hurt:
		return SHAKE_PLAYER_HURT_PX
	if is_stagger:
		return SHAKE_STAGGER_PX
	var px: float = SHAKE_HEAVY_PX if is_heavy else SHAKE_NONE_PX
	if is_crit:
		px += SHAKE_CRIT_BONUS_PX
	return px
