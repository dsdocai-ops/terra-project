extends State
## Player walking from Player.move_input along the isometric axes.
## Owned by player-controller. Sync: via Player (host position of record,
## local prediction for the owning peer, see SPEC-networking).

var _player: Player


func enter(_from: StringName) -> void:
	_player = actor as Player
	_player.play_directional("walk")


func physics_update(delta: float) -> void:
	if _player.move_input == Vector2.ZERO:
		machine.change_to(&"Idle")
		return
	var dir := Iso.input_to_world(_player.move_input)
	var target := dir * _player.move_speed()
	_player.velocity = _player.velocity.move_toward(target, Player.MOVE_ACCEL * delta)
	_player.set_facing(dir)
	_player.play_directional("walk")
	_player.move_and_slide()
	_player.clamp_to_camera()
