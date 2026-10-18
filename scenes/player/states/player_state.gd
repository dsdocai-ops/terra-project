class_name PlayerState
extends State
## Base for every player state: resolves the typed Player once.
## Owned by player-controller. Sync: via Player.

var player: Player


func _on_setup() -> void:
	player = actor as Player
	assert(player != null, "PlayerState must sit under a Player's StateMachine")
