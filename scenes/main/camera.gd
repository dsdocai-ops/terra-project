class_name GameCamera
extends Camera2D
## Follows one player, or frames every player in co-op by zooming out.
## Owned by player-controller. Sync: none, each peer runs its own camera
## over the replicated player positions.
##
## Targets come from set_targets(), or, when none were set, from the Player
## children of `track_container` (World/Players), so spawning a player is
## enough to be framed.
##
## The co-op movement limit is NOT derived from this node's state. It is the
## pure function coop_bounds(positions), computed from player positions and
## the fixed design viewport, so host and predicting client agree on it
## regardless of smoothing, zoom easing, or which camera is current
## (Player.apply_coop_clamp). The camera merely displays the same framing.
##
## Framing runs on physics ticks, the same clock that moves the players.
## Physics interpolation (project setting) then draws both between ticks, so
## a player holds still on screen while walking. Framing in _process instead
## moves the camera every rendered frame while players move only on ticks,
## which shows as player jitter.

const MIN_ZOOM := 0.6
const MAX_ZOOM := 1.0
## Base viewport the game is designed and stretched from (SPEC-foundation).
const DESIGN_VIEWPORT := Vector2(960, 540)
## World pixels kept free around the players' bounding box when fitting.
const FIT_MARGIN := 96.0
## World pixels inside the view edge that players are clamped to.
const EDGE_PADDING := 24.0
const ZOOM_LERP_SPEED := 6.0
## Offset in pixels at full trauma.
const MAX_SHAKE_PX := 12.0

## Node whose Player children are tracked when no explicit targets are set.
@export var track_container: NodePath
## Settings slider, 0 disables shake, 1 is full strength.
@export_range(0.0, 1.0) var screen_shake: float = 1.0

## Seedable so tests can make shake deterministic.
var rng := RandomNumberGenerator.new()
## Accumulated shake, 0 to 1. Offset amplitude is MAX_SHAKE_PX * trauma^2.
var trauma: float = 0.0

var _targets: Array[Player] = []
var _trauma_decay_per_second: float = 0.0
var _was_shaking: bool = false


func _init() -> void:
	# Engine default is idle; physics interpolation needs tick-rate smoothing.
	# world.tscn sets it too, because scene properties apply before the script.
	process_callback = Camera2D.CAMERA2D_PROCESS_PHYSICS


func _physics_process(delta: float) -> void:
	update_framing(delta)


## Explicit targets. An empty array falls back to `track_container`.
func set_targets(players: Array[Player]) -> void:
	_targets = players.duplicate()


## TODO(player-controller, week 3): exclude dead players once Dead exists;
## downed players stay framed so teammates can reach them.
func current_targets() -> Array[Player]:
	var result: Array[Player] = []
	if not _targets.is_empty():
		for p in _targets:
			if is_instance_valid(p) and p.is_inside_tree():
				result.append(p)
		return result
	if track_container.is_empty():
		return result
	var container := get_node_or_null(track_container)
	if container == null:
		return result
	for child in container.get_children():
		var p := child as Player
		if p != null:
			result.append(p)
	return result


func target_count() -> int:
	return current_targets().size()


func target_positions() -> Array[Vector2]:
	var positions: Array[Vector2] = []
	for p in current_targets():
		positions.append(p.global_position)
	return positions


## Zoom (1 = native, smaller = further out) that fits `bounds` plus
## FIT_MARGIN on every side into `viewport_size`, clamped to the allowed range.
static func fit_zoom(bounds: Rect2, viewport_size: Vector2) -> float:
	var needed := bounds.size + Vector2.ONE * FIT_MARGIN * 2.0
	var z := minf(viewport_size.x / needed.x, viewport_size.y / needed.y)
	return clampf(z, MIN_ZOOM, MAX_ZOOM)


static func focus_point(positions: Array[Vector2]) -> Vector2:
	if positions.is_empty():
		return Vector2.ZERO
	var sum := Vector2.ZERO
	for p in positions:
		sum += p
	return sum / positions.size()


static func bounds_of(positions: Array[Vector2]) -> Rect2:
	if positions.is_empty():
		return Rect2()
	var rect := Rect2(positions[0], Vector2.ZERO)
	for p in positions:
		rect = rect.expand(p)
	return rect


## World rectangle every player must stay inside when playing together:
## the design viewport at the un-eased fit zoom, centered on the centroid,
## shrunk by EDGE_PADDING. Deterministic across peers.
static func coop_bounds(positions: Array[Vector2]) -> Rect2:
	var zoom_level := fit_zoom(bounds_of(positions), DESIGN_VIEWPORT)
	var size := DESIGN_VIEWPORT / zoom_level
	return Rect2(focus_point(positions) - size * 0.5, size).grow(-EDGE_PADDING)


## One framing step: centroid position, eased zoom, shake offset.
## Public so tests and cutscenes can step it manually.
func update_framing(delta: float) -> void:
	var positions := target_positions()
	if not positions.is_empty():
		global_position = focus_point(positions)
		var target_zoom := fit_zoom(bounds_of(positions), get_viewport_rect().size)
		var t := 1.0 - exp(-ZOOM_LERP_SPEED * delta)
		zoom = zoom.lerp(Vector2.ONE * target_zoom, t)
	_update_shake(delta)


## World-space rectangle currently on screen. Uses the smoothed screen
## center, which lags global_position while position smoothing is on.
func view_rect() -> Rect2:
	var size := get_viewport_rect().size / zoom
	return Rect2(get_screen_center_position() - size * 0.5, size)


## Trauma-style shake: each call adds `strength` / MAX_SHAKE_PX trauma
## (capped at 1) and decays at a rate that lets that amount fade over
## `duration` seconds. Amplitude is MAX_SHAKE_PX * trauma^2, so stacked hits
## shake harder but fade quickly.
func shake(strength: float, duration: float) -> void:
	var added := clampf(strength / MAX_SHAKE_PX, 0.0, 1.0)
	trauma = minf(trauma + added, 1.0)
	if duration > 0.0:
		_trauma_decay_per_second = maxf(_trauma_decay_per_second, added / duration)


func _update_shake(delta: float) -> void:
	if trauma <= 0.0:
		if _was_shaking:
			offset = Vector2.ZERO
			_was_shaking = false
		return
	trauma = maxf(trauma - _trauma_decay_per_second * delta, 0.0)
	if trauma <= 0.0:
		_trauma_decay_per_second = 0.0
		offset = Vector2.ZERO
		_was_shaking = false
		return
	var amplitude := MAX_SHAKE_PX * trauma * trauma * screen_shake
	offset = Vector2(rng.randf_range(-amplitude, amplitude), rng.randf_range(-amplitude, amplitude))
	_was_shaking = true
