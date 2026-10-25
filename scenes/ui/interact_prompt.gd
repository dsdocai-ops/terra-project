class_name InteractPrompt
extends Node2D
## The small tooltip beside the nearest interactable ("[F] Open") and the press
## that uses it. Owned by ui-hud. Sync: none; the tooltip is local, and a press
## just calls the interactable's `interact(player)`, which already forwards to
## the host on a client. An interactable is any area on physics layer 6
## ("interactable") with `prompt_text` and `interact(player)`: dungeon furniture
## in its room and town buildings alike.

## Screen pixels from the player within which an interactable is offered.
const REACH: float = 56.0
const LIFT: Vector2 = Vector2(18.0, -34.0)
## Physics layer 6, "interactable" (project.godot layer_names).
const INTERACTABLE_MASK: int = 32

var _label: Label = null
var _target: Node2D = null


func _ready() -> void:
	z_index = 90
	_label = Label.new()
	_label.add_theme_font_size_override(&"font_size", 10)
	_label.add_theme_color_override(&"font_color", Color(0.91, 0.847, 0.69))
	_label.add_theme_color_override(&"font_outline_color", Color(0.05, 0.04, 0.03))
	_label.add_theme_constant_override(&"outline_size", 4)
	add_child(_label)
	hide()


func _physics_process(_delta: float) -> void:
	var player: Player = NetworkManager.players.get(NetworkManager.local_peer_id)
	_target = null
	if player != null and is_instance_valid(player) and not player.is_downed:
		_target = nearest(self, player.global_position)
	if _target == null:
		hide()
		return
	_label.text = prompt_for(key_name(), String(_target.get(&"prompt_text")))
	global_position = _target.global_position + LIFT
	show()


func _unhandled_input(event: InputEvent) -> void:
	if _target == null or not is_instance_valid(_target) or not event.is_action_pressed(&"interact"):
		return
	var player: Player = NetworkManager.players.get(NetworkManager.local_peer_id)
	if player == null:
		return
	get_viewport().set_input_as_handled()
	_target.call(&"interact", player)


## The tooltip text, e.g. "[F] Open".
static func prompt_for(key: String, action: String) -> String:
	return "[%s] %s" % [key, action]


## The keyboard key bound to the interact action, "F" if unbound.
static func key_name() -> String:
	for event: InputEvent in InputMap.action_get_events(&"interact"):
		var key := event as InputEventKey
		if key == null:
			continue
		var code: Key = key.keycode
		if code == KEY_NONE and key.physical_keycode != KEY_NONE:
			# The layout-aware label needs a real display server (not headless).
			if DisplayServer.get_name() == "headless":
				code = key.physical_keycode
			else:
				code = DisplayServer.keyboard_get_keycode_from_physical(key.physical_keycode)
		if code != KEY_NONE:
			return OS.get_keycode_string(code)
	return "F"


## True for an area that can be used: it has a prompt and an `interact` method.
static func is_usable(item: Object) -> bool:
	return item != null and item.has_method(&"interact") and &"prompt_text" in item \
			and not String(item.get(&"prompt_text")).is_empty()


## The closest usable interactable within REACH of `point`, or null.
static func nearest(from: Node2D, point: Vector2) -> Node2D:
	var query := PhysicsShapeQueryParameters2D.new()
	var circle := CircleShape2D.new()
	circle.radius = REACH
	query.shape = circle
	query.transform = Transform2D(0.0, point)
	query.collision_mask = INTERACTABLE_MASK
	query.collide_with_areas = true
	query.collide_with_bodies = false
	var best: Node2D = null
	var best_distance: float = INF
	for hit: Dictionary in from.get_world_2d().direct_space_state.intersect_shape(query, 16):
		var item := hit.get("collider") as Node2D
		if not is_usable(item):
			continue
		var distance: float = item.global_position.distance_to(point)
		if distance < best_distance:
			best_distance = distance
			best = item
	return best
