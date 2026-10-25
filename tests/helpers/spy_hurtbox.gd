class_name SpyHurtbox
extends Area2D
## Test double for Dev A's `Hurtbox` (combat-core, W2-A2) that reports every hit
## it is asked to receive to the harness's `SpyWorld`, so
## `Effect.deal_damage`'s delivery is recorded as a *damage call* rather than
## merely observed on the stub. Wired onto every player and target the trigger
## harness (`tests/helpers/effect_harness.gd`) builds; never used in a game
## scene.
##
## It is also where a harness case chooses whether the hit is announced on
## `Events.hit_landed`, which is the real hurtbox's other job (SPEC-combat-core:
## "compute damage via `Damage.compute`, pass to `Health`, ... emit
## `Events.hit_landed`"). `SpyWorld.announce_hits` controls that: off by default
## so a content case asserting a relic's damage is not surprised by its own hit
## echoing back through the bus, on for a chain case. `ProcHurtboxStub` is the
## same announce-always shape for the proc-limit tests.
##
## blocked on Dev A (W2-A2): the real hurtbox replaces this stub name for name.
##
## Sync: none — a test double. The real hurtbox is host-only and early-returns
## on clients.

## The recorder this hurtbox reports to. Set by the harness before the node's
## owner enters the tree; null means the hit is dropped unrecorded (an
## unwired double), never an error.
var world: SpyWorld = null


## Records the hit against this hurtbox's owner (its parent, which is the
## target `Effect.deal_damage` addressed) and, when the world asks for it,
## announces it on the bus exactly as the real hurtbox does.
func receive(hit: HitInfo) -> void:
	if world == null:
		return
	world.note_damage(get_parent(), hit)
	if world.announce_hits:
		Events.hit_landed.emit(hit)
