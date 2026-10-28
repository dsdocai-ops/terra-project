extends PlayerState
## Downed: a lethal hit with a teammate still standing lands here instead of
## Dead (W3-A5). The player cannot move and nothing takes them out of the
## state but a revive (back to Idle) or the bleed-out running out (Dead) —
## SPEC-player-controller: "Downed refuses everything but revive".
## Owned by player-controller. Sync: the host decides the down and the death
## (its `_on_died` enters this state); `is_downed` / `is_dead` replicate
## through StateSync, and the body's pose with them.
##
## The 30 s bleed-out and the revive hold run on the pure `DownedClock`
## (`scripts/player/downed_clock.gd`): entry starts the bleed-out, an exit
## clears it, and the host steps the clock from `Player.tick_downed` — a
## downed player's machine is stopped (`Player.simulates` is false), so this
## state's `physics_update` only ever holds the body still.


func enter(_from: StringName) -> void:
	player.velocity = Vector2.ZERO
	player.play_directional("idle")
	player.begin_bleed_out()


func exit(_to: StringName) -> void:
	player.stop_bleed_out()


## Only standing back up (a revive) or bleeding out may leave.
func can_exit(to: StringName) -> bool:
	return to == &"Idle" or to == &"Dead"


## A dead player is never downed again.
func can_enter(_from: StringName) -> bool:
	return not player.is_dead


func physics_update(_delta: float) -> void:
	# The body holds still. The bleed-out is ticked by the host's combat
	# timers (Player.tick_downed), because the machine is stopped while downed.
	player.velocity = Vector2.ZERO
