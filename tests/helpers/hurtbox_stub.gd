class_name HurtboxStub
extends Area2D
## Test double for Dev A's `Hurtbox` (combat-core, W2-A2), which is still a
## bare `Area2D` in `player.tscn`: it records every `receive(hit)` so
## `Effect.deal_damage`'s delivery can be asserted before the real component
## lands. Used by the effect tests; never used in a game scene.
##
## blocked on Dev A (W2-A2): the real hurtbox replaces this stub name for name.
## SPEC-combat-core is the contract — "`receive(hit)` on the host: ... compute
## damage via `Damage.compute`, pass to `Health`, apply knockback, apply
## statuses from `hit.statuses`, emit `Events.hit_landed`" — so the real one is
## also what announces an effect's hit on the bus; `deal_damage` itself never
## emits a combat event (SPEC-effect-system, "Emitters are the owning modules").
##
## Sync: none — a test double. The real hurtbox is host-only and early-returns
## on clients.

## Every hit this hurtbox was asked to receive, in order.
var received: Array[HitData] = []


func receive(hit: HitData) -> void:
	received.append(hit)
