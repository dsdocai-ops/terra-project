extends Node
## Enemy-side time multiplier for slow, stop, hit-stop, and rewind effects.
## Owned by time-manager. Week 1 stub: the API shape from SPEC-time-manager
## with pass-through behaviour (scale 1, no effects). Real implementation in
## week 2.
## Sync: host decides every time effect and broadcasts start events; expiry
## is computed locally. Never Engine.time_scale.

enum Group { PLAYER, ENEMY }

signal enemy_time_changed(scale: float)

var _groups: Dictionary[int, Group] = {}


## Current time multiplier for a node (1.0 = normal, 0.0 = stopped).
func scale_for(_node: Node) -> float:
	return 1.0


## Called in _ready by player and enemy scripts.
func set_group(node: Node, group: Group) -> void:
	_groups[node.get_instance_id()] = group


func slow_enemies(_factor: float, _seconds: float, _source: StringName) -> void:
	pass


func stop_enemies(_seconds: float, _source: StringName) -> void:
	pass


## Cancel a slow or stop early (e.g. Deadeye release).
func clear_source(_source: StringName) -> void:
	pass


func set_entity_scale(_node: Node, _factor: float, _seconds: float, _source: StringName) -> void:
	pass


## Freezes exactly `a` and `b` for `frames` physics frames.
func hit_stop(_a: Node, _b: Node, _frames: int) -> void:
	pass


## Scaled one-shot timer. Stub returns an unscaled SceneTree timer.
## TODO(time-manager): respect scale_for(node).
func timer(_node: Node, seconds: float) -> Signal:
	return get_tree().create_timer(seconds).timeout


func register_rewindable(_node: Node, _sampler: Callable, _restorer: Callable) -> void:
	pass


func unregister_rewindable(_node: Node) -> void:
	pass


func rewind(_node: Node, _seconds: float) -> void:
	pass
