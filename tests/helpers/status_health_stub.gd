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

## The `StatusEffects` child the heal path reads the penalty from — the entity's
## own component, which every fixture in the status tests installs.
const STATUS_NODE: NodePath = ^"StatusEffects"

## Mirrors the real component's fields. The status tests set both to the
## fixture's max HP.
var max_hp: int = 100
var current_hp: int = 100

## Every hit handed to `apply_damage()`, in order.
var hits: Array[HitData] = []

## Every amount handed to `heal()`, in order — including a zero. Separate from
## `healed_total` so "the heal path was never reached" (no entry) reads
## differently from "the heal path was reached and granted nothing" (a 0), which
## is the distinction Leech Fang's zero-damage case needs.
var heal_calls: Array[int] = []

## How much HP this entity has actually been healed for, after every status
## penalty — the "through the heal path" half of the TOXIN test: the assertion
## is on what landed, not on the multiplier alone.
var healed_total: int = 0


## Records `hit` and subtracts its `final_damage` from `current_hp`, exactly as
## the real `Health` treats a hit whose damage has already been computed.
func apply_damage(hit: HitData) -> bool:
	if hit == null:
		return false
	hits.append(hit)
	current_hp = maxi(current_hp - hit.final_damage, 0)
	return true


## Applies `amount` of healing the way the real `Health.heal()` will: the amount
## is first passed through the entity's `StatusEffects.healing_multiplier()`, so
## a toxic entity's healing arrives already halved, and the granted amount is
## what comes back. Returns the HP actually restored.
##
## blocked on Dev A (W2-A1, combat-core `Health`): the real heal is
## host-authoritative and emits `Events.player_healed(player, amount, source)`;
## this double is the swap-in that lets the status penalty be asserted through a
## heal rather than by reading the multiplier off the component.
func heal(amount: int) -> int:
	heal_calls.append(amount)
	var granted := maxi(amount, 0)
	var statuses: StatusEffects = get_parent().get_node_or_null(STATUS_NODE) as StatusEffects
	if statuses != null:
		granted = int(floor(float(granted) * statuses.healing_multiplier()))
	current_hp = mini(current_hp + granted, max_hp)
	healed_total += granted
	return granted


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