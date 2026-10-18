extends PlayerState
## Player walking from Player.move_input along the isometric axes.
## Owned by player-controller. Sync: via Player (host position of record,
## local prediction for the owning peer, see SPEC-networking).


func enter(_from: StringName) -> void:
	player.play_directional("walk")


func physics_update(delta: float) -> void:
	if player.move_input == Vector2.ZERO:
		machine.change_to(&"Idle")
		return
	var dir := Iso.input_to_world(player.move_input)
	var target := dir * player.move_speed()
	player.velocity = player.velocity.move_toward(target, Player.MOVE_ACCEL * delta)
	player.set_facing(dir)
	player.apply_coop_clamp(delta)
	player.move_and_slide()
