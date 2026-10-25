class_name HitInfo
extends RefCounted
## The payload of one hit: built by the attacker, copied per target, read by
## `Damage.compute`, `Hurtbox`, `Health` and every effect that listens to a hit.
## Owned by combat-core (SPEC-combat-core, "HitInfo"); it replaced stats-status's
## `HitData` stand-in by the 2026-10-21 decision, so there is one payload type.
## `is_crit` and `final_damage` are filled by `Damage.compute`, `from_behind` by
## `Hurtbox`.
## Sync: none. An ephemeral value object built by the attacker on the host.

## Element of a hit; statuses and combos key off it.
enum Element { NONE, FIRE, FROST, STORM, SHADOW, POISON, EARTH, BLOOD, VOID }

const AP_REFERENCE: float = 100.0
## A hit whose direction differs from the target's facing by more than this many
## degrees came from behind (SPEC-combat-core, "Hurtbox").
const BEHIND_ANGLE_DEGREES: float = 120.0
## Stun a hit applies unless its builder says otherwise.
const DEFAULT_HIT_STUN_SECONDS: float = 0.15

## The attacker entity: player, enemy, minion or turret.
var source: Node = null

## Raw damage before any scaling, from WeaponData / AbilityData ranks.
var base_damage: float = 0.0
## Caller-composed multiplicative effects (Backstab +75%, Far Shot, Revenge
## Pact x3, ...). Defaults to 1.0.
var multiplier: float = 1.0
## Added to the attacker's CRIT_CHANCE before the roll.
var bonus_crit_chance: float = 0.0
var element: Element = Element.NONE
var is_heavy: bool = false
## Poise drained from the target, filled by whoever builds the hit (the weapon
## controller from `AttackSpec.poise_damage`, enemy attacks from their pattern).
var poise_damage: float = 0.0
## Set by the target's poise logic before `hit_landed` when this hit broke its
## poise (or hit a 0-poise enemy), so feedback can give the stagger its tier.
var staggered: bool = false
## Set by Hurtbox's from-behind check; Rogue, Backstab, Geode Turtle and Heart
## Guard read it.
var from_behind: bool = false
## The player this hit is attributed to: the one whose weapon, ability, minion or
## proc produced it. Mirrors `HitInfo.owner_player`, whose spec comment is "for
## attribution of minion/turret/proc hits". `null` for a hit nothing attributes —
## a hazard's, or the test double `EventEmitterHelper` builds — so an unattributed
## hit is inert rather than credited to somebody.
##
## It is what makes an On Hit relic possible: `hit_landed` carries no `Player`
## argument (SPEC-effect-system's own comment: "hit.source / hit.owner_player /
## target in hit"), so the relics listening to it (W4-B6) filter on this field
## themselves — `Effect.listen()`'s player filter has nothing to read.
var owner_player: Player = null
## The entity the hit landed on, when whoever built the payload knows it: what
## "the same enemy" (Hungry Steel) and "splits on hit" (Splitting Shot) act on.
## The `target` SPEC-effect-system's `hit_landed` line names beside `source`
## and `owner_player`. `null` on a payload that never reached one, which
## every effect reading it treats as a skipped trigger rather than a crash.
var target: Node = null
var tags: Array[StringName] = []
## Statuses (and stacks) to apply to the target when the hit connects.
var statuses: Array[StatusApplication] = []
## Impulse along the hit direction; its length is the strength.
var knockback: Vector2 = Vector2.ZERO
var hit_stun_seconds: float = DEFAULT_HIT_STUN_SECONDS
var is_projectile: bool = false
## Set by an `about_to_die` handler (Second Wind, Undying, Twin Souls) to keep
## the target alive.
var prevented: bool = false
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
## x0.0); weapon hits return a flat 1.0. The week-12 balance pass revises the
## curve in the golden file.
func ability_power_scale(ability_power: float) -> float:
	if not scales_with_ability_power:
		return 1.0
	return maxf(1.0 + (ability_power - AP_REFERENCE) / AP_REFERENCE, 0.0)


## Whether a hit that reached a target facing `target_facing` from
## `direction_to_attacker` (target toward attacker) came from behind: the two
## differ by more than `BEHIND_ANGLE_DEGREES`. A zero vector on either side has no
## angle, so it is never "behind".
static func is_from_behind(target_facing: Vector2, direction_to_attacker: Vector2) -> bool:
	if target_facing.is_zero_approx() or direction_to_attacker.is_zero_approx():
		return false
	return absf(rad_to_deg(target_facing.angle_to(direction_to_attacker))) > BEHIND_ANGLE_DEGREES


## A copy for one target: the template stays untouched so the next target (or the
## next swing) starts from the same numbers. Arrays are copied, `StatusApplication`
## entries are shared (they are never mutated after the builder makes them).
func copy() -> HitInfo:
	var clone := HitInfo.new()
	clone.source = source
	clone.owner_player = owner_player
	clone.target = target
	clone.base_damage = base_damage
	clone.multiplier = multiplier
	clone.bonus_crit_chance = bonus_crit_chance
	clone.element = element
	clone.statuses = statuses.duplicate()
	clone.knockback = knockback
	clone.hit_stun_seconds = hit_stun_seconds
	clone.is_heavy = is_heavy
	clone.poise_damage = poise_damage
	clone.staggered = staggered
	clone.is_projectile = is_projectile
	clone.is_crit = is_crit
	clone.from_behind = from_behind
	clone.final_damage = final_damage
	clone.tags = tags.duplicate()
	clone.proc_depth = proc_depth
	clone.prevented = prevented
	clone.force_crit = force_crit
	clone.scales_with_ability_power = scales_with_ability_power
	return clone
