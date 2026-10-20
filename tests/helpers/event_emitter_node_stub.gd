class_name EventEmitterNodeStub
extends Node
## A bare `Node` double for the `Events` signals whose argument is declared as
## `Node` until its owning module lands (`room_entered`/`room_cleared`'s Room,
## `projectile_fired`'s Projectile). `stub_kind` names which one this instance
## stands in for, so a listener that logs what it was handed can say `room`
## rather than `<Node#…>`. `pickup_collected`'s `Pickup` is no longer one of
## these: run-economy declared the real class at W4-B8 (G12) and the emitter
## builds one.
## Owned by tests (effect-system). Sync: none — a test double, never spawned in
## a live scene.



## Which argument this instance stands in for: `&"room"`, `&"projectile"` or
## `&"source"`.
var stub_kind: StringName = &"node"
