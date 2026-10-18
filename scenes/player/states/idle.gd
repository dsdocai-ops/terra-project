extends State
## Player standing still. Owned by player-controller. Sync: via Player.

var _player: Player


func enter(_from: StringName) -> void:
	_player = actor as Player
	_player.velocity = Vector2.ZERO
	_player.play_directional("idle")


func physics_update(_delta: float) -> void:
	if _player.move_input != Vector2.ZERO:
		machine.change_to(&"Move")
