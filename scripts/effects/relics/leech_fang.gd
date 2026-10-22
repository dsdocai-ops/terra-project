class_name LeechFangEffect
extends Effect
## Leech Fang — design doc 9.1 no. 13: "heal 2% of damage dealt". Owned by relics
## (W4-B6, goal G7).
##
## Every hit this player lands heals them `HEAL_FRACTION` of the damage that hit
## actually dealt. The amount comes from `hit.final_damage` — what the pipeline
## computed and applied — rather than from `base_damage`: the design doc's
## sentence is "damage *dealt*", so a crit heals more and a hit that was reduced
## to nothing heals nothing. The double carries the point; the assertion in the
## batch's case is on the HP that landed, not on the fraction.
##
## **Where the healing goes.** Through the player's own `Health` component
## (combat-core, W2-A1), asked for by name and guarded by `has_method()` — the C6
## shape. The real component owns `current_hp`, clamps at `max_hp` and passes the
## amount through `StatusEffects.healing_multiplier()` so a Toxic holder's leech
## arrives already halved; this relic decides only the amount
## (**blocked on Dev A (W2-A1)**). An entity with no `Health` node is a warned
## no-op rather than a crash.
##
## **The relic does not announce the heal.** The real component emits
## `Events.player_healed(player, amount, source)` itself, and the emitters are the
## owning modules (SPEC-effect-system, "Events bus") — the same rule
## `Effect.deal_damage()` follows for `hit_landed`. A second emitter here would
## double every heal on the co-op HUD and in anything else listening.
##
## **Nothing is asked for when nothing was dealt.** A non-positive heal is
## skipped before the component is touched, so `heal_requests()` never counts a
## zero: "the hit dealt nothing" and "the hit dealt something that rounded to no
## healing" must not read the same.
##
## **Which hits count.** This player's `proc_depth == 0` hits, for the reason
## Echo Blade documents: `hit_landed` carries no `Player` argument for
## `Effect.listen()` to filter on, so a teammate's hit — and this player's own
## procs — must be filtered off the payload's `owner_player` here.
##
## `max_stacks = 1` in the data file: the rate is the design doc's 2% and does
## not compound with copies; sustain relics that scale with copies are the ones
## the doc says "(stacks)" about, and this line does not.
##
## Sync: host-only (SPEC-relics, "Multiplayer ownership"). The healed `current_hp`
## reaches clients through the entity's `StateSync`, which is the real component's
## business.

## The fraction of the damage dealt that returns as healing. Design doc 9.1
## no. 13: "heal 2% of damage dealt".
const HEAL_FRACTION: float = 0.02
## The method the heal is requested through. combat-core's `Health.heal()` —
## `StatusEffects.HEALTH_METHOD` is the *damage* entry point (`apply_damage`), so
## this one is named here and is the seam's whole contract
## (**blocked on Dev A (W2-A1)**).
const HEAL_METHOD: StringName = &"heal"

## Every heal this effect has asked its player's `Health` for, in order. A read
## for the batch's case and the debug overlay; empty means the heal path was
## never reached, which is not the same as a requested zero.
var heal_requests: Array[int] = []


func _on_attach() -> void:
	listen(Events.hit_landed, _on_hit_landed)


## One of this player's own hits: leech a fraction of what it dealt.
func _on_hit_landed(hit: HitData) -> void:
	if not _is_my_hit(hit):
		return
	_leech(hit.final_damage)


## True when `hit` is a hit this effect's own player landed, and not one of the
## procs this player's own effects produced.
func _is_my_hit(hit: HitData) -> bool:
	if player == null or hit == null or hit.owner_player != player:
		return false
	return hit.proc_depth == 0


## Heals this player `HEAL_FRACTION` of `damage`, rounded to whole HP the way
## every other whole-number amount in the damage path is. Nothing is asked for
## when that comes to zero.
func _leech(damage: int) -> void:
	var amount: int = roundi(float(damage) * HEAL_FRACTION)
	if amount <= 0:
		return
	var health: Node = _health_node()
	if health == null:
		push_warning("[effect] %s: the player has no Health to heal, %d dropped" % [
			source_id(), amount])
		return
	heal_requests.append(amount)
	health.call(HEAL_METHOD, amount)


## This player's `Health` component, or null when it carries none — or carries
## one that cannot heal. A `has_method` check rather than an `is Health` cast: the
## tests install a recording double in the component's place, exactly as
## `Effect._status_component()` does for `StatusEffects`, so the leak can be
## asserted without a real component on every fixture.
func _health_node() -> Node:
	if player == null:
		return null
	var node: Node = player.get_node_or_null(StatusEffects.HEALTH_NODE)
	if node == null or not node.has_method(HEAL_METHOD):
		return null
	return node