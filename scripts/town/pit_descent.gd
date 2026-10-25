class_name PitDescent
extends Area2D
## The pit's edge: always open, so the party can climb back down even before the
## Tavern is built. Using it opens the same Dive screen the Tavern does. Owned by
## town. Sync: the host's, like the Tavern; a client's press does nothing yet.

signal descend_requested(peer_id: int)

## Physics layer 6, "interactable" (project.godot layer_names).
const INTERACTABLE_LAYER: int = 32
const REACH: float = 48.0

var prompt_text: String = "Descend into the pit"


func _init() -> void:
	name = "PitDescent"
	collision_layer = INTERACTABLE_LAYER
	collision_mask = 0
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = REACH
	shape.shape = circle
	add_child(shape)


func interact(player: Player) -> void:
	if not NetworkManager.is_host:
		return
	descend_requested.emit(NetworkManager.local_peer_id if player == null else player.peer_id)
