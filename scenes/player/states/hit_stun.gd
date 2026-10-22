extends PlayerState
## Player flinched by a hit: no input, only the knockback impulse moves them,
## for Player.hit_stun_left seconds. Then Move if the move key is held, else
## Idle. Owned by combat-core (W2-A3). Sync: host runs it, StateSync carries
## the resulting position.


func enter(_from: StringName) -> void:
	player.play_directional("idle")


func physics_update(delta: float) -> void:
	player.decay_knockback(delta)
	player.velocity = player.knockback_velocity
	player.move_and_slide()
	if player.is_on_wall():
		# Walls block the impulse. Stop it here so it does not grind along them.
		player.knockback_velocity = Vector2.ZERO
	player.hit_stun_left -= delta
	if player.hit_stun_left > 0.0:
		return
	var next: StringName = &"Move" if player.move_input != Vector2.ZERO else &"Idle"
	if machine.change_to(next):
		machine.current.physics_update(0.0)
