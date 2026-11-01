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
	if arc_degrees > 180.0:
		# The hitbox of a fan this wide is its convex hull (WeaponController), so
		# the wedge shows the hull too.
		var hull: PackedVector2Array = Geometry2D.convex_hull(points)
		if hull.size() > 1 and hull[0] == hull[hull.size() - 1]:
			hull.remove_at(hull.size() - 1)
		return hull
	return points


func _draw() -> void:
	if _seconds_left <= 0.0:
		return
	var elapsed: float = clampf(1.0 - _seconds_left / _seconds_total, 0.0, 1.0)
	var fade: float = 1.0 - elapsed
	if shape == AttackSpec.Shape.CIRCLE:
		_draw_shockwave(elapsed, fade)
	else:
		_draw_swoosh(elapsed, fade)


## A crescent that sweeps across the arc: a bright leading edge and a tail that
## fades behind it, so the swing reads as motion rather than a hitbox outline.
func _draw_swoosh(elapsed: float, fade: float) -> void:
	var half: float = deg_to_rad(arc_degrees) * 0.5
	var sweep: float = 1.0 - pow(1.0 - clampf(elapsed * 2.2, 0.0, 1.0), 3.0)
	var head: float = lerpf(-half, half, sweep)
	var tail: float = -half
	var steps: int = ARC_SEGMENTS
	var bright: Color = color.lerp(Color.WHITE, 0.65)
	var outer := PackedVector2Array()
	var inner := PackedVector2Array()
	var outer_colors := PackedColorArray()
	var inner_colors := PackedColorArray()
	for index: int in range(steps + 1):
		var along: float = float(index) / float(steps)
		var angle: float = lerpf(tail, head, along)
		var dir: Vector2 = Vector2.RIGHT.rotated(angle)
		# The band is thick at the head and thins to nothing at the tail.
		var thickness: float = reach * lerpf(0.04, 0.5, along)
		outer.append(dir * reach)
		inner.append(dir * (reach - thickness))
		var alpha: float = along * along * fade
		outer_colors.append(Color(bright.r, bright.g, bright.b, alpha * 0.95))
		inner_colors.append(Color(color.r, color.g, color.b, alpha * 0.1))
	# The first frame has no sweep yet; its quads would be degenerate slivers.
	for index: int in range(steps if sweep > 0.03 else 0):
		var quad := PackedVector2Array([outer[index], outer[index + 1], inner[index + 1], inner[index]])
		var quad_colors := PackedColorArray([outer_colors[index], outer_colors[index + 1], inner_colors[index + 1], inner_colors[index]])
		draw_polygon(quad, quad_colors)
	# Faint ghost of the real hit area so the reach still reads, then the cutting edge.
	var area: PackedVector2Array = outline()
	if area.size() >= 3:
		draw_colored_polygon(area, Color(color.r, color.g, color.b, FILL_ALPHA * 0.25 * fade))
	var lead: Vector2 = Vector2.RIGHT.rotated(head)
	draw_line(lead * reach * 0.55, lead * reach, Color(1.0, 1.0, 1.0, EDGE_ALPHA * fade), 2.0)
	draw_polyline(outer, Color(bright.r, bright.g, bright.b, EDGE_ALPHA * 0.7 * fade), 1.5)


## A ring that bursts outward from the attacker with a bright flash at the centre.
func _draw_shockwave(elapsed: float, fade: float) -> void:
	var burst: float = 1.0 - pow(1.0 - clampf(elapsed * 1.8, 0.0, 1.0), 3.0)
	var radius: float = reach * lerpf(0.35, 1.0, burst)
	var bright: Color = color.lerp(Color.WHITE, 0.6)
	draw_circle(Vector2.ZERO, reach, Color(color.r, color.g, color.b, FILL_ALPHA * 0.3 * fade))
	draw_circle(Vector2.ZERO, radius * 0.7, Color(color.r, color.g, color.b, FILL_ALPHA * 0.5 * fade))
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, ARC_SEGMENTS * 3, Color(bright.r, bright.g, bright.b, EDGE_ALPHA * fade), 3.0 * fade + 1.0)
	draw_arc(Vector2.ZERO, radius * 0.8, 0.0, TAU, ARC_SEGMENTS * 3, Color(color.r, color.g, color.b, 0.5 * fade), 1.5)
