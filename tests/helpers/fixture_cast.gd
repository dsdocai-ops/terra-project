class_name FixtureCast
extends AbilityCast
## Trivial cast scene for the ability tests: counts how often the host performed
## it, and deals no hit. Owned by abilities (test helper). Sync: none.

## How many times `_perform` ran on this node. The tests read it to tell a host
## cast from a client's visual copy.
var performs: int = 0


func _perform() -> void:
	performs += 1
