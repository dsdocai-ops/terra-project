class_name GameCamera
extends Camera2D
## Follows one player, or frames every player in co-op by zooming out.
## Owned by player-controller. Sync: none, each peer runs its own camera
## over the replicated player positions.
##
## Targets come from set_targets(), or, when none were set, from the Node2D
## children of `track_container` (World/Players), so spawning a player is
## enough to be framed. Movement clamping (Player.clamp_to_camera) keeps
## everyone inside view_rect() when there is more than one target.

const MIN_ZOOM := 0.6
const MAX_ZOOM := 1.0
## World pixels kept free around the players' bounding box when fitting.
const FIT_MARGIN := 96.0
## World pixels inside the view edge that players are clamped to.
const EDGE_PADDING := 24.0
const ZOOM_LERP_SPEED := 6.0

## Node whose Node2D children are tracked when no explicit targets are set.
@export var track_container: NodePath
## Settings slider, 0 disables shake, 1 is full strength.
@export_range(0.0, 1.0) var screen_shake: float = 1.0

## Seedable so tests can make shake deterministic.
var rng := RandomNumberGenerator.new()

var _targets: Array[Node2D] = []
var _shake_strength: float = 0.0
var _shake_time_left: float = 0.0
var _shake_duration: float = 0.0


func _process(delta: float) -> void:
	update_framing(delta)


## Explicit targets. An empty array falls back to `track_container`.
func set_targets(targets: Array[Node2D]) -> void:
	_targets = targets.duplicate()


func current_targets() -> Array[Node2D]:
	var result: Array[Node2D] = []
	if not _targets.is_empty():
		for t in _targets:
			if is_instance_valid(t) and t.is_inside_tree():
				result.append(t)
		return result
	if track_container.is_empty():
		return result
	var container := get_node_or_null(track_container)
	if container == null:
		return result
	for child in container.get_children():
		var node := child as Node2D
		if node != null:
			result.append(node)
	return result


func target_count() -> int:
	return current_targets().size()


## Zoom (1 = native, smaller = further out) that fits `bounds` plus
## FIT_MARGIN on every side into `viewport_size`, clamped to the allowed range.
static func fit_zoom(bounds: Rect2, viewport_size: Vector2) -> float:
	var needed := bounds.size + Vector2.ONE * FIT_MARGIN * 2.0
	var z := minf(viewport_size.x / needed.x, viewport_size.y / needed.y)
	return clampf(z, MIN_ZOOM, MAX_ZOOM)


static func focus_point(targets: Array[Node2D]) -> Vector2:
	if targets.is_empty():
		return Vector2.ZERO
	var sum := Vector2.ZERO
	for t in targets:
		sum += t.global_position
	return sum / targets.size()


static func bounds_of(targets: Array[Node2D]) -> Rect2:
	if targets.is_empty():
		return Rect2()
	var rect := Rect2(targets[0].global_position, Vector2.ZERO)
	for t in targets:
		rect = rect.expand(t.global_position)
	return rect


## One framing step: centroid position, eased zoom, shake offset.
## Public so tests and cutscenes can step it manually.
func update_framing(delta: float) -> void:
	var targets := current_targets()
	if not targets.is_empty():
		global_position = focus_point(targets)
		var target_zoom := fit_zoom(bounds_of(targets), get_viewport_rect().size)
		var t := 1.0 - exp(-ZOOM_LERP_SPEED * delta)
		zoom = zoom.lerp(Vector2.ONE * target_zoom, t)
	_update_shake(delta)


## World-space rectangle currently visible.
func view_rect() -> Rect2:
	var size := get_viewport_rect().size / zoom
	return Rect2(global_position - size * 0.5, size)


## Clamps a world position so it stays EDGE_PADDING inside the view.
func clamp_to_view(point: Vector2) -> Vector2:
	var rect := view_rect().grow(-EDGE_PADDING)
	return point.clamp(rect.position, rect.end)


## Trauma-style shake: offset up to `strength` pixels, fading out
## quadratically over `duration` seconds. Repeated calls take the larger
## values rather than stacking.
func shake(strength: float, duration: float) -> void:
	_shake_strength = maxf(_shake_strength, strength)
	_shake_duration = maxf(_shake_duration, duration)
	_shake_time_left = maxf(_shake_time_left, duration)


func _update_shake(delta: float) -> void:
	if _shake_time_left <= 0.0:
		offset = Vector2.ZERO
		return
	_shake_time_left -= delta
	if _shake_time_left <= 0.0:
		_shake_time_left = 0.0
		_shake_strength = 0.0
		_shake_duration = 0.0
		offset = Vector2.ZERO
		return
	var t := _shake_time_left / _shake_duration
	var amplitude := _shake_strength * t * t * screen_shake
	offset = Vector2(rng.randf_range(-amplitude, amplitude), rng.randf_range(-amplitude, amplitude))
