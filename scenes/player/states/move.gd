extends State
## Player walking from Player.move_input. Owned by player-controller.
## Sync: via Player. Velocity and facing math land in W1-A6.

var _player: Player


func enter(_from: StringName) -> void:
	_player = actor as Player
	_player.play_directional("walk")


func physics_update(_delta: float) -> void:
	if _player.move_input == Vector2.ZERO:
		machine.change_to(&"Idle")
		return
