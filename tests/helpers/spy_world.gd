class_name SpyWorld
extends EffectSpawnerSpy
## The trigger harness's recorder: every node an effect asked the world to
## spawn, every projectile it fired, and every hit that landed on a target —
## in order, with the content id and proc depth that produced each. SPEC-effect-
## system's "Interfaces provided" names it as the harness's assertion surface:
## "asserts spawns, stat changes, statuses, and damage via a `SpyWorld`".
##
## It extends `EffectSpawnerSpy` rather than duplicating it — that double
## already records `spawn_node()` / `spawn_projectile()` and then runs the real
## `EffectSpawner` base, so the harness asserts *that the seam was asked* and
## *what came back* at once. What is added here is the other half: damage. A hit
## reaches a target through the target's `SpyHurtbox`, which calls
## `note_damage()`; spawns are recorded by the inherited overrides.
##
## It is a real `EffectSpawner` subclass, so the player's `EffectHost` can be
## handed one and every helper on the effect path runs unmodified. Content cases
## read it directly (`world.spawns`, `world.damage_calls`) or through the
## harness's query and assertion helpers.
##
## Sync: none — a test double. The sealed cracks it stands in for are host-only.

## Every hit delivered to a `SpyHurtbox`, in order: `{target: Node, hit: HitData}`.
## Recorded in delivery order, so a case can assert the *nth* hit as well as the
## total.
var damage_calls: Array[Dictionary] = []
## When true, a `SpyHurtbox` announces each recorded hit on `Events.hit_landed`,
## as the real hurtbox does. False by default: a content case asserting "the
## relic dealt 12 damage" wants that fact recorded, not re-fed to the relic that
## produced it. A chain case sets it true.
var announce_hits: bool = false


## Records one landed hit. Called by `SpyHurtbox.receive()`; nothing else.
func note_damage(target: Node, hit: HitData) -> void:
	damage_calls.append({"target": target, "hit": hit})


## How many children this world has allowed to be spawned, across everything
## attached, or only those attributed to `source_id` when it is given. The
## unfiltered form is what "the relic spawned one trail" is asserted with; the
## filtered form proves the spawn belongs to that relic and not to another
## effect on the same player.
func spawn_count(source_id: StringName = &"") -> int:
	if source_id == &"":
		return spawns.size()
	return spawns_for(source_id).size()


## Every recorded spawn attributed to `source_id`, in order. Each entry is the
## `EffectSpawnerSpy` shape: `{scene, position, setup, proc_source_id,
## proc_depth, node}`.
func spawns_for(source_id: StringName) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	for entry: Dictionary in spawns:
		if StringName(entry["proc_source_id"]) == source_id:
			found.append(entry)
	return found


## How many hits landed on `target`, or on anything when it is null.
func damage_count(target: Node = null) -> int:
	if target == null:
		return damage_calls.size()
	return damage_hits(target).size()


## Every hit that landed on `target`, in delivery order.
func damage_hits(target: Node) -> Array[HitData]:
	var found: Array[HitData] = []
	for entry: Dictionary in damage_calls:
		if entry["target"] == target:
			found.append(entry["hit"] as HitData)
	return found


## The `base_damage` of every hit that landed on `target`, summed. This is the
## damage the *effect* asked for (the payload it built), not what a hurtbox's
## `Damage.compute` would turn it into — so a case asserts the relic's numbers
## without needing Dev A's formula.
func damage_total(target: Node) -> float:
	var total: float = 0.0
	for hit: HitData in damage_hits(target):
		total += hit.base_damage
	return total
