class_name StatusEffectsStub
extends Node
## Test double for the `StatusEffects` component (stats-status, W4-B4 / goal
## G20), which does not exist yet: it records every `apply_status` call so
## `Effect.apply_status`'s call site can be asserted before the real component
## lands. Attached to the player scene's `StatusEffects` node by the effect
## tests; never used in a game scene.
##
## blocked on Dev B (W4-B4, goal G20): the real component replaces this stub
## member for member. The signature is the spec's
## `apply_status(status, stacks, source: Node)` (SPEC-stats-status, "Statuses"),
## which is what `Effect.apply_status` calls — the third argument is the effect
## that applied it, so `Events.status_applied(target, status, stacks, source)`
## can name its origin.
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
