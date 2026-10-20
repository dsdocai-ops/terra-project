class_name RelicFxRootStub
extends Node2D
## The double for an **FX-with-gameplay root** — the trail, the clone, the
## freezing patch a relic spawns (`EffectSpawner.spawn_node()`, whose doc comment
## calls the class "clones, slip zones, totems"). It records the arming call the
## effect made on it, which is the only thing a dodge relic can assert about a
## root whose gameplay another lane owns:
##
## - `arm_trail(status)` — Ember Boots. The trail harms what stands in it.
## - `arm_fuse(seconds)` — Mirror Step. The clone detonates after the fuse.
## - `arm_patch(status)` — Frostwalkers. The patch applies to what crosses it.
##
## The real roots are art-audio's `scenes/vfx/relic_proc_<tag>.tscn` and the
## gameplay inside them (the hurtbox, the slip, the burn) is **blocked on Dev A
## (W4-A4)** — combat-core's FX-with-gameplay spawner and the damage path. This
## double is the C6 seam: the effect asks by name, a missing root means the call
## never happens (a guarded no-op, not an error), and swapping the real scene in
## is a data change on the relic, not a change to the effect.
##
## `armed` distinguishes "the effect did not arm it" from "it armed it with the
## first enum value" — an unarmed double and one armed with `Status.BURN` (which
## is 0) would otherwise read the same.
##
## Owned by relics (tests). Sync: none — a test double. The real roots are
## host-only; whatever they spawn reaches clients through the world's spawner.
##
## blocked on art-audio (W4-B12/B13): the relic proc scenes and their SFX.

## True once any `arm_*()` call arrived. Paired with `armed_status` /
## `fuse_seconds` so a case can tell an absent arming from a zero-valued one.
var armed: bool = false
## The status the root was armed with, or -1 when it was never armed.
var armed_status: int = -1
## The fuse the root was armed with, or 0.0 when it was never armed.
var fuse_seconds: float = 0.0
## Every `arm_*()` call in order, as `{method: StringName, argument: Variant}` —
## so a case can also assert that a root was armed *exactly once*.
var arm_calls: Array[Dictionary] = []


## Arms the root as a trail that applies `status` to whatever it touches.
func arm_trail(status: int) -> void:
	_record(&"arm_trail", status)
	armed_status = status


## Arms the root as a patch that applies `status` to whatever crosses it.
func arm_patch(status: int) -> void:
	_record(&"arm_patch", status)
	armed_status = status


## Arms the root as a clone that detonates after `seconds`.
func arm_fuse(seconds: float) -> void:
	_record(&"arm_fuse", seconds)
	fuse_seconds = seconds


func _record(method: StringName, argument: Variant) -> void:
	armed = true
	arm_calls.append({"method": method, "argument": argument})
