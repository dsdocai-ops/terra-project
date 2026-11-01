class_name RecordingHurtbox
extends Hurtbox
## A Hurtbox that keeps every hit it is handed instead of running damage, so a
## test can count what a zone or cast struck. Owned by combat-core (test helper).
## Sync: none. Never used in a game scene.

## Every hit `receive` was handed, in order.
var received: Array[HitInfo] = []


func receive(hit: HitInfo) -> bool:
	received.append(hit)
	return true
