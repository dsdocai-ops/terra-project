class_name Damage
extends RefCounted
## The single damage formula every hit in the game uses. Owned by stats-status.
## Sync: runs only on the host (Hurtbox.receive calls it there); clients never
## compute damage, they render replicated results.
##
##   raw         = hit.base_damage * (attacker.ATTACK / 100.0) * hit.ability_power_scale(attacker.ABILITY_POWER)
##   crit        = roll(attacker.CRIT_CHANCE + hit.bonus_crit_chance), forced true when the hit says so or the target has MARK
##   crit_mult   = 1.5 + attacker.CRIT_DAMAGE if crit else 1.0
##   status_mult = 1.0 (+0.25 Kindling on BURN) (+1.0 Permafrost on FREEZE, once)
##                      (+UNRAVEL stacks * 0.1) -- the whole term is
##                      StatusEffects.incoming_damage_multiplier(), one read here
##                      so its parts cannot be counted twice or forgotten
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
##
## This is the one place a status's damage contribution is computed, and it runs
## only on the host (see "Sync" above). It *spends* two things on the target's
## component: the MARK that forces the crit, and the pending freeze double that
## the status term is — both are consumed by the hit they land on, so a caller
## must call this exactly once per connecting hit and must not read
## `incoming_damage_multiplier()` on its own to preview a hit.

const MIN_DAMAGE: int = 1
## The `EffectHost` child an entity carrying relics has, and where the two
## attacker-side status terms (Kindling, Permafrost) are read from. The same node
## name and the same path `StatusEffects` uses for an entity's own host, because
## it is the same node.
const EFFECT_HOST_NODE: NodePath = ^"EffectHost"
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


## The attacking entity's `EffectHost` — where the formula's two attacker-side
## relic terms (Kindling, Permafrost) are read from — or null when the attacker
## is a bare `StatBlock`: a hazard, a status tick, or a fixture. The path is
## `parent/EffectHost`, the same one `StatusEffects` uses for an entity's own
## host, so a relic is read off the entity that holds it rather than configured
## here (SPEC-project: content is data).
static func _attacker_host(attacker: StatBlock) -> EffectHost:
	if attacker == null:
		return null
	var parent: Node = attacker.get_parent()
	if parent == null:
		return null
	return parent.get_node_or_null(EFFECT_HOST_NODE) as EffectHost


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
## hit.final_damage. `rng` is the host's
## seeded generator for the run; null uses Damage's fallback generator. A forced
## crit — the hit's own flag, or a MARK on the target — short-circuits, so it
## consumes no draw (W3-B1's rule, now reachable from a status as well).
##
## `target_statuses` is the target's `StatusEffects` component and is where the
## formula's `status_mult` term comes from, in full: UNRAVEL's "+10 % all damage
## taken per stack", Kindling's "+0.25 on BURN" and Permafrost's "+1.0 on FREEZE,
## once" — `incoming_damage_multiplier()` composes the three, and this method
## hands it the attacker's `EffectHost` (read off the attacker's parent) so the
## two attacker-side terms can be looked up. It is a trailing optional argument
## so every week-2 caller and the golden table keep their exact behaviour: a null
## component leaves `status_mult` at 1.0, no relic is consulted and no status is
## spent.
##
## Called once per connecting hit: the call spends the target's MARK and its
## pending freeze double, which is what makes each land on exactly one hit.
static func compute(attacker: StatBlock, target: StatBlock, hit: HitInfo, \
		rng: RandomNumberGenerator = null, target_statuses: StatusEffects = null) -> int:
	var crit_rng: RandomNumberGenerator = _crit_rng(rng)
	var raw := hit.base_damage * (attacker.get_value(StatBlock.Stat.ATTACK) / ATTACK_REFERENCE) \
		* hit.ability_power_scale(attacker.get_value(StatBlock.Stat.ABILITY_POWER))
	# MARK's row: "Next damaging hit is a guaranteed crit, then consumed". Read
	# and consumed here, before the roll below, so a marked hit draws nothing from
	# the generator — and consumed on the hit it forces, so the flag the crit is
	# decided from and the consumption cannot disagree.
	var forced := hit.force_crit
	if target_statuses != null and target_statuses.mark_forces_crit():
		forced = true
		target_statuses.consume_mark()
	var crit := forced \
		or crit_rng.randf_range(CRIT_ROLL_MIN, CRIT_ROLL_MAX) < (attacker.get_value(StatBlock.Stat.CRIT_CHANCE) + hit.bonus_crit_chance)
	var crit_mult := (BASE_CRIT_MULTIPLIER + attacker.get_value(StatBlock.Stat.CRIT_DAMAGE)) if crit else 1.0
	var status_mult := 1.0
	if target_statuses != null:
		status_mult = target_statuses.incoming_damage_multiplier(_attacker_host(attacker))
	var defense := maxf(target.get_value(StatBlock.Stat.DEFENSE), 0.0)
	var mitigation := MITIGATION_BASE / (MITIGATION_BASE + defense)
	var final := roundi(raw * crit_mult * status_mult * hit.multiplier * mitigation)
	hit.is_crit = crit
	hit.final_damage = maxi(final, MIN_DAMAGE)
	return hit.final_damage
