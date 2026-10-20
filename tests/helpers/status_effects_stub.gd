class_name StatusEffectsStub
extends Node
## Test double for the `StatusEffects` component (stats-status, W4-B4 / goal
## G20). The real component landed in G20 (`scripts/components/status_effects.gd`)
## and is what the stats-status tests drive; this stub stays in the effect tests
## because it *records* every `apply_status` call, so `Effect.apply_status`'s
## call site can be asserted without a real component on every effect fixture.
## Attached to the player scene's `StatusEffects` node by the effect tests; never
## used in a game scene.
##
## The real component replaces this stub member for member. The signature is the
## spec's `apply_status(status, stacks, source: Node)` (SPEC-stats-status,
## "Statuses"), which is what `Effect.apply_status` calls — the third argument is
## the effect that applied it, so
## `Events.status_applied(target, status, stacks, source)` can name its origin.
## `status` stays a plain `int` here on purpose: a recording double takes
## anything, including the bogus ids the component refuses.
##
## Sync: none — a test double. The real component's stacks are replicated by
## the entity's `StateSync`; its modifier lists are host-only.

## Every `apply_status` call, in order: {status: int, stacks: int, source: Node}.
var applications: Array[Dictionary] = []


func apply_status(status: int, stacks: int, source: Node) -> void:
	applications.append({"status": status, "stacks": stacks, "source": source})


## The stacks of the most recent application of `status`, or 0 when it was
## never applied. Lets a test read a call back without re-walking the list.
func stacks(status: int) -> int:
	for i: int in range(applications.size() - 1, -1, -1):
		if int(applications[i]["status"]) == status:
			return int(applications[i]["stacks"])
	return 0


## The statuses this double has been asked for, in the component's own enum order
## and with a zero-stack application left out — the real `active_statuses()`
## contract, which is what a relic reading a corpse's statuses (Domino, W4-B6/G8a)
## asks for. Derived from the recorded applications because the double records
## calls rather than state: the read is "which statuses were applied", and the
## stacks stay `stacks()`'s own read, which is the most recent application's.
func active_statuses() -> Array[int]:
	var found: Array[int] = []
	for status: int in StatusEffects.Status.values():
		if stacks(status) > 0:
			found.append(status)
	return found
