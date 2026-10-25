class_name SlashArc
extends Node2D
## The swing visual (SPEC-combat-core "Hit feedback"): a translucent wedge or
## disc drawn with the attack's real reach and arc so players can see the
## hitbox. Placeholder art until AR-3. Owned by combat-core. Sync: none; it is
## local presentation. `WeaponController` plays it on every peer: the owner and
## the host from their Attack state, other clients from the host's swing RPC.
## It times itself out, so a peer that never calls `stop` still clears it.

const ARC_SEGMENTS: int = 12
const FILL_ALPHA: float = 0.32
const EDGE_ALPHA: float = 0.8

var shape: AttackSpec.Shape = AttackSpec.Shape.ARC
var reach: float = 0.0
var arc_degrees: float = 0.0
var color: Color = Color(1.0, 1.0, 1.0, 1.0)

var _seconds_total: float = 0.0
var _seconds_left: float = 0.0


func _ready() -> void:
	z_index = 5
	visible = false
	set_physics_process(false)


## True while the wedge is on screen.
func is_playing() -> bool:
	return _seconds_left > 0.0


## Shows the swing for `seconds`. `p_reach` already includes any charge bonus.
## Projectile attacks have no melee shape and draw nothing.
func play(p_shape: AttackSpec.Shape, p_reach: float, p_arc_degrees: float, dir: Vector2, seconds: float, p_color: Color) -> void:
	if p_shape == AttackSpec.Shape.PROJECTILE or seconds <= 0.0:
		stop()
		return
	shape = p_shape
	reach = p_reach
	arc_degrees = p_arc_degrees
	color = p_color
	rotation = dir.angle() if shape == AttackSpec.Shape.ARC else 0.0
	_seconds_total = seconds
	_seconds_left = seconds
	visible = true
	set_physics_process(true)
	queue_redraw()


func stop() -> void:
	_seconds_left = 0.0
	visible = false
	set_physics_process(false)
	queue_redraw()


func _physics_process(delta: float) -> void:
	step(delta)


## Advances the timer by real time. Public so tests can step it.
func step(delta: float) -> void:
	if _seconds_left <= 0.0:
		return
	_seconds_left -= delta
	if _seconds_left <= 0.0:
		stop()
	else:
		queue_redraw()


## The swing's outline in local space: the polygon the wedge is filled with. A
## circle returns a ring of points so tests can measure the reach.
func outline() -> PackedVector2Array:
	var points := PackedVector2Array()
	if shape == AttackSpec.Shape.CIRCLE:
		for index: int in ARC_SEGMENTS * 2:
			points.append(Vector2.RIGHT.rotated(TAU * float(index) / float(ARC_SEGMENTS * 2)) * reach)
		return points
	var half: float = deg_to_rad(arc_degrees) * 0.5
	points.append(Vector2.ZERO)
	for step_index: int in range(ARC_SEGMENTS + 1):
		points.append(Vector2.RIGHT.rotated(lerpf(-half, half, float(step_index) / float(ARC_SEGMENTS))) * reach)
	return points


func _draw() -> void:
	if _seconds_left <= 0.0:
		return
	var fade: float = clampf(_seconds_left / _seconds_total, 0.0, 1.0)
	var points: PackedVector2Array = outline()
	if points.size() < 3:
		return
	draw_colored_polygon(points, Color(color.r, color.g, color.b, FILL_ALPHA * fade))
	var closed: PackedVector2Array = points.duplicate()
	closed.append(points[0])
	draw_polyline(closed, Color(color.r, color.g, color.b, EDGE_ALPHA * fade), 1.5)
