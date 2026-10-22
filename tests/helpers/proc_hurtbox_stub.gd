class_name ProcHurtboxStub
extends HurtboxStub
## Test double for Dev A's `Hurtbox` (combat-core, W2-A2) that does what the
## real one does to the bus as well as what `HurtboxStub` does: it records the
## hit *and then announces it* — `Events.hit_landed.emit(hit)`, after the damage
## would have been applied. `HurtboxStub` only records, which is enough to
## assert delivery but cannot drive a chain: a proc chain advances because the
## hit an effect produced is announced back onto the bus, and the announcement
## is the hurtbox's (SPEC-combat-core — "compute damage via `Damage.compute`,
## pass to `Health`, apply knockback, apply statuses from `hit.statuses`, emit
## `Events.hit_landed`").
##
## The announced hit is the same object `Effect.deal_damage` stamped, so the
## `proc_depth` on the bus is the depth the helper produced — which is what the
## depth gate reads. Used by `tests/unit/test_proc_limits.gd`; never used in a
## game scene.
##
## blocked on Dev A (W2-A2): the real hurtbox replaces this stub name for name.
##
## Sync: none — a test double. The real hurtbox is host-only and early-returns
## on clients; a client re-emits `hit_landed` from replicated state instead.


func receive(hit: HitData) -> void:
	super(hit)
	Events.hit_landed.emit(hit)
