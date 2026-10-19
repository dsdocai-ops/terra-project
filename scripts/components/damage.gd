class_name Damage
extends RefCounted
## The single damage formula every hit in the game uses. Owned by stats-status.
## Sync: runs only on the host (Hurtbox.receive calls it there); clients never
## compute damage, they render replicated results.
##
##   raw         = hit.base_damage * (attacker.ATTACK / 100.0) * hit.ability_power_scale(attacker.ABILITY_POWER)
##   crit        = roll(attacker.CRIT_CHANCE + hit.bonus_crit_chance), forced true when the target has MARK
##   crit_mult   = 1.5 + attacker.CRIT_DAMAGE if crit else 1.0
##   status_mult = 1.0 (+0.25 Kindling on BURN, +1.0 Permafrost on FREEZE once,
##                      +UNRAVEL stacks * 0.1 -- land with StatusEffects, week 4)
##   defense     = max(target.DEFENSE, 0)
##   mitigation  = 100.0 / (100.0 + defense)
##   final       = round(raw * crit_mult * status_mult * hit.multiplier * mitigation), min 1 on a connecting hit
##
## The crit roll uses Godot's global RNG, which GameState seeds per run once
## run-economy lands (week 3); until then tests seed it directly. hit.multiplier
## is where effects like Backstab / Far Shot / Revenge Pact land; the caller
## composes them multiplicatively.

const MIN_DAMAGE: int = 1
const ATTACK_REFERENCE: float = 100.0
const MITIGATION_BASE: float = 100.0
const BASE_CRIT_MULTIPLIER: float = 1.5


## Returns the final damage for a connecting hit and fills hit.is_crit /
## hit.final_damage. `hit` is the week-2 HitData mirror of combat-core's
## HitInfo; the fields the formula reads match by name.
static func compute(attacker: StatBlock, target: StatBlock, hit: HitData) -> int:
	var raw := hit.base_damage * (attacker.get_value(StatBlock.Stat.ATTACK) / ATTACK_REFERENCE) \
		* hit.ability_power_scale(attacker.get_value(StatBlock.Stat.ABILITY_POWER))
	var crit := hit.force_crit or randf() < (attacker.get_value(StatBlock.Stat.CRIT_CHANCE) + hit.bonus_crit_chance)
	var crit_mult := (BASE_CRIT_MULTIPLIER + attacker.get_value(StatBlock.Stat.CRIT_DAMAGE)) if crit else 1.0
	var status_mult := 1.0  # status terms land with StatusEffects (week 4)
	var defense := maxf(target.get_value(StatBlock.Stat.DEFENSE), 0.0)
	var mitigation := MITIGATION_BASE / (MITIGATION_BASE + defense)
	var final := roundi(raw * crit_mult * status_mult * hit.multiplier * mitigation)
	hit.is_crit = crit
	hit.final_damage = maxi(final, MIN_DAMAGE)
	return hit.final_damage
