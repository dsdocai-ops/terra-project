class_name ActiveRelicStub
extends Effect
## A stand-in for an **active** relic's effect script: the `actives themselves
## arrive week 8` half of W4-B7, so the controller's tests need a relic whose
## `Effect` answers `activate()` and states whether its charges refill per room.
## Owned by relics (W4-B7, PLAN G11). Sync: none — a test double on the host.
##
## Write-then-read: `activations` is how a case proves the controller called the
## relic's own seam exactly once per applied activation, and `applies = false` is
## the negative control for a relic that refuses to fire (an empty charge, a
## target out of range, a locked elite affix) — the controller must then refuse
## the activation and spend nothing.
##
## `refill_on_room` is the relic's "where stated" (SPEC-relics "Active relics":
## "charges refill per room where stated"): the controller refills a slot on
## `room_entered` only when this answers true, which is what makes the refill a
## property of the relic rather than of every active.

## How many times `activate()` was called. Every call counts, including one that
## answered false, so a case can tell "the controller refused before reaching the
## relic" from "the relic refused".
var activations: int = 0
## What `activate()` answers. True unless a case flips it.
var applies: bool = true
## What `refills_charges_per_room()` answers. False unless a case flips it.
var refill_on_room: bool = false


func activate() -> bool:
	activations += 1
	return applies


func refills_charges_per_room() -> bool:
	return refill_on_room
