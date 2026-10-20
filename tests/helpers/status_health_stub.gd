class_name StatusHealthStub
extends Node
## Test double for Dev A's `Health` component (combat-core, W2-A1), carrying the
## one entry point status ticking goes through: `apply_damage(hit)`. It records
## every hit it is handed so a test can assert a status's damage without a real
## `Health`, which does not exist yet.
##
## blocked on Dev A (W2-A1, combat-core `Health`): SPEC-combat-core's
## "Interfaces provided" fixes the signature as `apply_damage(hit: HitInfo)`, so
## the tick hands over a `HitData` — the week-2 mirror whose damage-relevant
## field names already match `HitInfo` — and the swap-in is a type rename.
## Ownership: the real `Health` is host-authoritative and its `current_hp` is
## replicated by the entity's `StateSync`; this double is host-side test state.
##
## Sync: none — a test double, attached to a test fixture's entity by the
## stats-status tests; never used in a game scene.

## Mirrors the real component's fields. The status tests set both to the
## fixture's max HP.
var max_hp: int = 100
var current_hp: int = 100

## Every hit handed to `apply_damage()`, in order.
var hits: Array[HitData] = []


## Records `hit` and subtracts its `final_damage` from `current_hp`, exactly as
## the real `Health` treats a hit whose damage has already been computed.
func apply_damage(hit: HitData) -> bool:
	if hit == null:
		return false
	hits.append(hit)
	current_hp = maxi(current_hp - hit.final_damage, 0)
	return true


## How many hits landed, and the damage they added up to. Two reads rather than
## one because a tick that deals 0 damage still lands a hit.
func hit_count() -> int:
	return hits.size()


func total_damage() -> int:
	var total := 0
	for hit: HitData in hits:
		total += hit.final_damage
	return total


## The damage of the last hit, or 0 when none landed.
func last_damage() -> int:
	if hits.is_empty():
		return 0
	return hits[hits.size() - 1].final_damage


## The `HitData.Element` of the last hit, or `NONE` when none landed.
func last_element() -> int:
	if hits.is_empty():
		return HitData.Element.NONE
	return hits[hits.size() - 1].element