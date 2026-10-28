extends PlayerState
## Dead: out for the rest of the floor (W3-A5) — reached solo at once (downed
## is skipped) or when the 30 s bleed-out expires in Downed. Nothing moves or
## revives a dead player mid-floor; the next floor's fresh run stands them
## back up through `Player.reset_for_run`, the one exit Dead allows.
## Owned by player-controller. Sync: `is_dead` is host-owned and replicates
## through StateSync with the body's pose; the Dead state itself is entered by
## the host's death path.


func enter(_from: StringName) -> void:
	player.velocity = Vector2.ZERO


## Dead for the rest of the floor: nothing leaves but the next floor's fresh
## run (reset_for_run stands the player back up at Idle).
func can_exit(to: StringName) -> bool:
	return to == &"Idle"


func physics_update(_delta: float) -> void:
	player.velocity = Vector2.ZERO
