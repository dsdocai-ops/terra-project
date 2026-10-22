class_name DodgeSeamStub
extends Node
## The double for the seam a dodge relic asks when it wants something the Dodge
## state does: **Rebound Spring**'s wall bounce.
##
## A relic cannot move the player — the dodge's reflection is player-controller's
## movement (Dev A, SPEC-player-controller's Dodge state) — so the relic asks a
## `DodgeSeam` child node for it and the ask is what a case can assert:
## `request_wall_bounce()` counted in `wall_bounce_requests`. The effect looks the
## node up by name and checks `has_method()` before calling, so a player without
## the seam is a guarded no-op rather than an error — the C6 shape the whole
## project uses for a provider another lane owns.
##
## The real seam is Dev A's: when the Dodge state lands it (W2-A8) a child node
## named `DodgeSeam` with this method replaces this double, and the effect does
## not change.
##
## Owned by relics (tests). Sync: none — a test double. The real dodge is
## host-only and replicates as movement, not as a call.
##
## blocked on Dev A (W2-A8, the Dodge state): the reflection itself.

## How many times the relic asked for a wall bounce.
var wall_bounce_requests: int = 0


## The ask: the Dodge state should reflect this dodge off the wall it hit.
func request_wall_bounce() -> void:
	wall_bounce_requests += 1
