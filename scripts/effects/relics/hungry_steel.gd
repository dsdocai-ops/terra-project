class_name HungrySteelEffect
extends Effect
## Hungry Steel — design doc 9.1 no. 9: "each hit on the same enemy deals +5%
## more (stacks)". Owned by relics (W4-B6, goal G6).
##
## Per **enemy**: every hit this player lands on one enemy deepens that enemy's
## own count, so the nth hit on it is worth `PER_HIT_STACK_BONUS * n` — 5 %, then
## 10 %, then 15 % — and a second enemy starts its own count at 5 % again. The
## count is keyed by the enemy's *instance id*, never by the node itself: a node
## held as a key would keep a dead enemy alive, and an id is what
## `stacks_for(enemy)` can answer for a live one.
##
## **Where the "+5 % more" lands, and why the relic deals it.** The damage of the
## hit that just landed is computed by the hurtbox *before* the event is
## announced — SPEC-combat-core's `Hurtbox.receive` order is "compute damage via
## `Damage.compute`, pass to `Health`, apply knockback, apply statuses ..., emit
## `Events.hit_landed`" — so a relic listening to `hit_landed` cannot add to a
## hit that has already been delivered. What it does instead is deal *the part
## the bonus is worth*: the same enemy, the same element,
## `base_damage * n * PER_HIT_STACK_BONUS`, through `deal_damage()`. The total
## damage the enemy takes is therefore the same as if the weapon's own hit had
## carried the bonus, and the rider's own hit reaches the same hurtbox path a
## weapon's does.
##
## `damage_multiplier_for(enemy)` publishes the other half of the answer —
## `1.0 + n * 5 %` — as the read the damage pipeline consumes when the seam for
## it exists (**blocked on Dev A, W2-A2's `Hurtbox`/`Damage.compute`**: the
## pipeline has no "ask the effects on this attacker what they are worth" step
## yet, so today the rider is the only route and the numbers are identical to
## what the pipeline would produce). When it lands, the relic's rider is removed
## or the pipeline consumes the read — a one-line choice, recorded in HANDOFF.md
## as a decision rather than left to drift.
##
## The rider carries this effect's own id, so rule 2 stops the rider's own
## `hit_landed` — the real hurtbox announces every hit it delivers — from
## deepening the count it has just deepened; without it each hit would feed
## itself and the relic would be a Bonfire.
##
## `max_stacks = 3` in the data file: the design doc's "(stacks)" fixes that the
## relic stacks but gives no count, so the batch chooses three and every copy
## deepens the same step — the nth hit is worth `bonus * n * copies` (recorded as
## a decision in HANDOFF.md, where the week-12 balance pass can move it).
##
## Sync: host-only (SPEC-relics, "Multiplayer ownership"). The rider's damage
## travels the hurtbox path, so clients see it exactly as they see a weapon's.

## The bonus one landed hit is worth, per copy held. Design doc 9.1 no. 9: "+5%
## more", and the data file's description states the same 5%.
const PER_HIT_STACK_BONUS: float = 0.05

## How many hits this player has landed on each enemy, keyed by
## `instance_id()`. An enemy absent from it has been hit zero times.
var _stacks: Dictionary[int, int] = {}


func _on_attach() -> void:
	listen(Events.hit_landed, _on_hit_landed)


## How many hits this effect's player has landed on `enemy`: 0 for one it has
## never hit, and 0 for a null or freed one rather than a stale count.
func stacks_for(enemy: Node) -> int:
	if enemy == null or not is_instance_valid(enemy):
		return 0
	return _stacks.get(enemy.get_instance_id(), 0)


## The multiplier a hit on `enemy` is worth right now: 1.0 for an enemy this
## player has never hit (no bonus at all), otherwise 1 + 5 % per landed hit,
## times the copies of this relic held. The read the damage pipeline takes once
## it has a step for it.
func damage_multiplier_for(enemy: Node) -> float:
	return 1.0 + float(stacks_for(enemy)) * PER_HIT_STACK_BONUS * float(stacks)


## One of this player's own hits: deepen that enemy's count and deal the extra
## the new count has earned.
func _on_hit_landed(hit: HitInfo) -> void:
	if not _is_my_hit(hit):
		return
	var enemy: Node = hit.target
	if enemy == null:
		return
	var count: int = stacks_for(enemy) + 1
	_stacks[enemy.get_instance_id()] = count
	deal_damage(enemy, _rider_for(hit, count))


## The hit the bonus is worth: this player's blow again, on the same enemy, for
## the fraction that enemy's count has earned. A fresh payload rather than the
## triggering hit — that one has already been computed, applied and announced,
## and this is a second, smaller blow.
func _rider_for(hit: HitInfo, count: int) -> HitInfo:
	var rider := HitInfo.new()
	rider.base_damage = hit.base_damage * float(count) * float(stacks) * PER_HIT_STACK_BONUS
	rider.element = hit.element
	rider.owner_player = player
	rider.target = hit.target
	var own_tag: Array[StringName] = [source_id()]
	rider.tags = own_tag
	return rider


## True when `hit` is a hit this effect's own player landed, and not one of the
## procs this player's own effects produced.
func _is_my_hit(hit: HitInfo) -> bool:
	if player == null or hit == null or hit.owner_player != player:
		return false
	return hit.proc_depth == 0