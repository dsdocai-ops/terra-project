class_name HitData
extends RefCounted
## The hit payload Damage.compute reads. Owned by stats-status.
## A week-2 mirror of combat-core's HitInfo (which has not landed yet): it
## carries exactly the damage-relevant fields the formula needs
## (base_damage, multiplier, bonus_crit_chance, element, is_heavy,
## from_behind, tags) plus the two flags Damage.compute consults directly
## (force_crit whether or not the caller forced it, scales_with_ability_power
## for the ability-power term). is_crit and final_damage are filled by
## Damage.compute. When Dev A's
## HitInfo lands, compute can be re-pointed at it — the field names match.
## Sync: none. An ephemeral value object built by the attacker on the host.

## Element of a hit. Statuses/combos consume this in week 4; week 2 only
## needs the enum to exist so the payload mirrors HitInfo.
enum Element { NONE, FIRE, FROST, STORM, SHADOW, POISON, EARTH, BLOOD, VOID }

const AP_REFERENCE: float = 100.0

## Raw damage before any scaling, from WeaponData / AbilityData ranks.
var base_damage: float = 0.0
## Caller-composed multiplicative effects (Backstab +75%, Far Shot, Revenge
## Pact x3, ...). Defaults to 1.0.
var multiplier: float = 1.0
## Added to the attacker's CRIT_CHANCE before the roll.
var bonus_crit_chance: float = 0.0
var element: Element = Element.NONE
var is_heavy: bool = false
## Set by Hurtbox's from-behind check; Rogue and Backstab read it.
var from_behind: bool = false
var tags: Array[StringName] = []
## How many effect links deep this hit is (SPEC-effect-system, "Proc chain
## limits"). A weapon or ability hit a player landed is 0; a hit an `Effect`
## produces through `deal_damage` is its trigger's depth + 1. `Effect.listen`'s
## dispatch wrapper drops events whose hit has reached `Effect.MAX_PROC_DEPTH`
## (3), so a chain of relics cannot recurse — while the hit itself, this object,
## is still delivered and still damages (W4-B3, goal G16). The per-frame spawn
## cap on top of that is goal G18.
var proc_depth: int = 0
## True when this hit forces a crit without rolling: the hit's own business, for
## a caller that already decided (a guaranteed-crit ability, a scripted tutorial
## hit). A MARK on the *target* is no longer a reason to set it — `StatusEffects`
## landed in G20/G21 and `Damage.compute` reads `mark_forces_crit()` off the
## target's own component (G23, 2026-10-20), consuming the mark on the one hit it
## forces. Either route short-circuits before the crit roll, so neither draws.
var force_crit: bool = false
## Abilities set this so their damage scales with ABILITY_POWER. Weapon hits
## keep the default (no scaling, multiplier stays 1.0).
var scales_with_ability_power: bool = false
## Filled by Damage.compute.
var is_crit: bool = false
## Filled by Damage.compute.
var final_damage: int = 0


## The `ability_power_scale` term from the damage formula. Ability hits scale
## linearly around the AP reference (AP 100 -> x1.0, AP 150 -> x1.5, AP 0 ->
## x0.0); weapon hits return a flat 1.0. The exact curve is HitInfo's
## (combat-core) once it lands; the week-12 balance pass revises it in the
## golden file.
func ability_power_scale(ability_power: float) -> float:
	if not scales_with_ability_power:
		return 1.0
	return maxf(1.0 + (ability_power - AP_REFERENCE) / AP_REFERENCE, 0.0)
