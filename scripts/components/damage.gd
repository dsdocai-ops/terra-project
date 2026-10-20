class_name Damage
extends RefCounted
## The single damage formula every hit in the game uses. Owned by stats-status.
## Sync: runs only on the host (Hurtbox.receive calls it there); clients never
## compute damage, they render replicated results.
##
##   raw         = hit.base_damage * (attacker.ATTACK / 100.0) * hit.ability_power_scale(attacker.ABILITY_POWER)
##   crit        = roll(attacker.CRIT_CHANCE + hit.bonus_crit_chance), forced true when the target has MARK
##   crit_mult   = 1.5 + attacker.CRIT_DAMAGE if crit else 1.0
##   status_mult = 1.0 (+UNRAVEL stacks * 0.1, read off the target's
##                      StatusEffects -- landed in G22; Kindling's +0.25 on BURN
##                      and Permafrost's +1.0 on FREEZE are the attacker-side
##                      terms G23 adds beside it)
##   defense     = max(target.DEFENSE, 0)
##   mitigation  = 100.0 / (100.0 + defense)
##   final       = round(raw * crit_mult * status_mult * hit.multiplier * mitigation), min 1 on a connecting hit
##
## The crit roll draws from a seeded RandomNumberGenerator: the caller passes the
## host's per-run generator so a seed replays the same crit sequence, and a
## caller that passes none rolls on Damage's own fallback generator (clock-seeded
## once, same pattern as GameState's host seed roll) — never a global roll
## function. hit.multiplier is where effects like Backstab / Far Shot / Revenge
## Pact land; the caller composes them multiplicatively.

const MIN_DAMAGE: int = 1
const ATTACK_REFERENCE: float = 100.0
const MITIGATION_BASE: float = 100.0
const BASE_CRIT_MULTIPLIER: float = 1.5
## The unit interval the crit roll compares against CRIT_CHANCE, named so the
## draw reads as a range rather than a magic pair.
const CRIT_ROLL_MIN: float = 0.0
const CRIT_ROLL_MAX: float = 1.0

## The generator used when a caller passes none. Created on first use and seeded
## from clock entropy, so repeated runs differ while the draw itself is always a
## seeded-generator call site. Host-only: only the host ever rolls a crit.
static var _fallback_rng: RandomNumberGenerator = null


## The generator the crit roll draws from: the caller's when one is supplied,
## otherwise the shared fallback above.
static func _crit_rng(rng: RandomNumberGenerator) -> RandomNumberGenerator:
	if rng != null:
		return rng
	if _fallback_rng == null:
		_fallback_rng = RandomNumberGenerator.new()
		_fallback_rng.seed = int(Time.get_unix_time_from_system() * 1000.0) ^ Time.get_ticks_usec()
	return _fallback_rng


## Returns the final damage for a connecting hit and fills hit.is_crit /
## hit.final_damage. `hit` is the week-2 HitData mirror of combat-core's
## HitInfo; the fields the formula reads match by name. `rng` is the host's
## seeded generator for the run; null uses Damage's fallback generator. A forced
## crit (MARK) short-circuits, so it consumes no draw.
##
## `target_statuses` is the target's `StatusEffects` component, and it is where
## the formula's `status_mult` term comes from: UNRAVEL's "+10 % all damage taken
## per stack" (G22). It is a trailing optional argument so every week-2 caller
## and the golden table keep their exact behaviour — a null component leaves
## `status_mult` at 1.0 — and so the attacker-side terms (Kindling's BURN bonus,
## Permafrost's FREEZE bonus) can be added beside it by G23 without a second
## signature change.
static func compute(attacker: StatBlock, target: StatBlock, hit: HitData, \
		rng: RandomNumberGenerator = null, target_statuses: StatusEffects = null) -> int:
	var crit_rng: RandomNumberGenerator = _crit_rng(rng)
	var raw := hit.base_damage * (attacker.get_value(StatBlock.Stat.ATTACK) / ATTACK_REFERENCE) \
		* hit.ability_power_scale(attacker.get_value(StatBlock.Stat.ABILITY_POWER))
	var crit := hit.force_crit \
		or crit_rng.randf_range(CRIT_ROLL_MIN, CRIT_ROLL_MAX) < (attacker.get_value(StatBlock.Stat.CRIT_CHANCE) + hit.bonus_crit_chance)
	var crit_mult := (BASE_CRIT_MULTIPLIER + attacker.get_value(StatBlock.Stat.CRIT_DAMAGE)) if crit else 1.0
	var status_mult := 1.0
	if target_statuses != null:
		status_mult = target_statuses.damage_taken_multiplier()
	var defense := maxf(target.get_value(StatBlock.Stat.DEFENSE), 0.0)
	var mitigation := MITIGATION_BASE / (MITIGATION_BASE + defense)
	var final := roundi(raw * crit_mult * status_mult * hit.multiplier * mitigation)
	hit.is_crit = crit
	hit.final_damage = maxi(final, MIN_DAMAGE)
	return hit.final_damage
