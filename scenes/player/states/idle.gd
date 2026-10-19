extends PlayerState
## Player standing still: decelerates to a stop, keeps its last facing.
## Owned by player-controller. Sync: via Player.


func enter(_from: StringName) -> void:
	player.play_directional("idle")


func physics_update(delta: float) -> void:
	if player.move_input != Vector2.ZERO:
		# Hand this frame to Move so input is never a frame late.
		if machine.change_to(&"Move"):
			machine.current.physics_update(delta)
		return
	if player.velocity != Vector2.ZERO:
		player.velocity = player.velocity.move_toward(Vector2.ZERO, player.move_friction() * delta)
		player.apply_coop_clamp(delta)
		player.move_and_slide()
