extends State
## Player standing still: decelerates to a stop, keeps its last facing.
## Owned by player-controller. Sync: via Player.

var _player: Player


func enter(_from: StringName) -> void:
	_player = actor as Player
	_player.play_directional("idle")


func physics_update(delta: float) -> void:
	if _player.move_input != Vector2.ZERO:
		machine.change_to(&"Move")
		return
	if _player.velocity != Vector2.ZERO:
		_player.velocity = _player.velocity.move_toward(Vector2.ZERO, Player.MOVE_FRICTION * delta)
		_player.move_and_slide()
