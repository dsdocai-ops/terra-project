extends PlayerState
## Player standing still: decelerates to a stop, keeps its last facing.
## Owned by player-controller. Sync: via Player.


func enter(_from: StringName) -> void:
	player.play_directional("idle")


func physics_update(delta: float) -> void:
	if player.move_input != Vector2.ZERO:
		machine.change_to(&"Move")
		return
	if player.velocity != Vector2.ZERO:
		player.velocity = player.velocity.move_toward(Vector2.ZERO, Player.MOVE_FRICTION * delta)
		player.apply_coop_clamp(delta)
		player.move_and_slide()
