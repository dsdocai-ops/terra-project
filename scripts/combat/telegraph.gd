class_name Telegraph
extends Node2D
## The ground shape that shows an enemy attack coming (SPEC-combat-core
## "Telegraph"): an outline that fills from 0 to 100% over the windup. Owned by
## combat-core. Sync: none; every peer draws it from the enemy's replicated
## `telegraph_progress` and `aim_dir`. Drawn as a faint danger zone with a charging fill and a glowing leading edge.
## Shapes: circle, cone, line and ring (a band between two radii that fills
## outward).

const OUTLINE_COLOR: Color = Color(1.0, 0.25, 0.2, 0.9)
const FILL_COLOR: Color = Color(1.0, 0.25, 0.2, 0.35)
const ARC_STEPS: int = 12
const OUTLINE_WIDTH: float = 1.5

var shape: AttackPattern.TelegraphShape = AttackPattern.TelegraphShape.CIRCLE
## x = length (or radius), y = width in px (cone: width in degrees).
var size: Vector2 = Vector2(48.0, 48.0)
var direction: Vector2 = Vector2.RIGHT
## How many times _draw has run, and the shape it drew last (tests read these:
## the dummy renderer cannot be inspected).
var draw_count: int = 0
var last_drawn: AttackPattern.TelegraphShape = AttackPattern.TelegraphShape.CIRCLE
## 0..1 while a windup runs; negative hides the telegraph.
var progress: float = -1.0:
	set(value):
		if is_equal_approx(value, progress):
			return
		progress = value
		visible = progress >= 0.0
		queue_redraw()


func _ready() -> void:
	visible = false
	z_index = -1


func configure(pattern: AttackPattern, dir: Vector2) -> void:
	shape = pattern.telegraph_shape
	size = pattern.telegraph_size
	direction = dir
	queue_redraw()


## The radii of a RING telegraph at fill `fill` (0..1) for `ring_size` (x = outer
## radius, y = band width): the band's inner and outer edge, and how far out the
## fill has reached. The fill sweeps from the inner edge to the outer one.
static func ring_geometry(ring_size: Vector2, fill: float) -> Dictionary:
	var outer: float = maxf(ring_size.x, 0.0)
	var inner: float = clampf(outer - maxf(ring_size.y, 0.0), 0.0, outer)
	return {"inner": inner, "outer": outer, "filled_to": lerpf(inner, outer, clampf(fill, 0.0, 1.0))}


func _draw() -> void:
	if progress < 0.0:
		return
	var fill: float = clampf(progress, 0.0, 1.0)
	draw_count += 1
	last_drawn = shape
	# The danger zone darkens and brightens as the strike nears, and the edge of
	# the fill glows so the windup reads as a charge rather than a debug shape.
	var body := Color(FILL_COLOR.r, FILL_COLOR.g, FILL_COLOR.b, lerpf(0.16, 0.5, fill))
	var zone := Color(FILL_COLOR.r, FILL_COLOR.g, FILL_COLOR.b, 0.12)
	var rim := Color(1.0, lerpf(0.35, 0.8, fill), lerpf(0.25, 0.5, fill), lerpf(0.55, 1.0, fill))
	var outline_color := Color(OUTLINE_COLOR.r, OUTLINE_COLOR.g, OUTLINE_COLOR.b, lerpf(0.5, 0.95, fill))
	match shape:
		AttackPattern.TelegraphShape.CIRCLE:
			draw_circle(Vector2.ZERO, size.x, zone)
			draw_circle(Vector2.ZERO, size.x * fill, body)
			draw_arc(Vector2.ZERO, size.x, 0.0, TAU, 32, outline_color, OUTLINE_WIDTH)
			draw_arc(Vector2.ZERO, size.x * fill, 0.0, TAU, 32, rim, 2.0)
		AttackPattern.TelegraphShape.CONE:
			var half: float = deg_to_rad(size.y) * 0.5
			var base: float = direction.angle()
			draw_colored_polygon(_sector(base, half, size.x), zone)
			if fill > 0.02:
				draw_colored_polygon(_sector(base, half, size.x * fill), body)
			draw_polyline(_sector(base, half, size.x) + PackedVector2Array([Vector2.ZERO]), outline_color, OUTLINE_WIDTH)
			draw_polyline(_arc_points(base, half, size.x * fill), rim, 2.0)
		AttackPattern.TelegraphShape.LINE:
			var across: Vector2 = direction.orthogonal() * size.y * 0.5
			var far: Vector2 = direction * size.x
			var near_fill: Vector2 = direction * size.x * fill
			draw_colored_polygon(PackedVector2Array([-across, -across + far, across + far, across]), zone)
			if fill > 0.02:
				draw_colored_polygon(PackedVector2Array([-across, -across + near_fill, across + near_fill, across]), body)
			draw_polyline(PackedVector2Array([-across, -across + far, across + far, across, -across]), outline_color, OUTLINE_WIDTH)
			draw_line(-across + near_fill, across + near_fill, rim, 2.0)
		AttackPattern.TelegraphShape.RING:
			var ring: Dictionary = ring_geometry(size, fill)
			var outer_r: float = ring["outer"]
			var inner_r: float = ring["inner"]
			var filled_r: float = ring["filled_to"]
			draw_arc(Vector2.ZERO, outer_r, 0.0, TAU, 40, outline_color, OUTLINE_WIDTH)
			if inner_r > 0.0:
				draw_arc(Vector2.ZERO, inner_r, 0.0, TAU, 40, outline_color, OUTLINE_WIDTH)
			var swept: float = filled_r - inner_r
			if swept > 0.5:
				draw_arc(Vector2.ZERO, inner_r + swept * 0.5, 0.0, TAU, 40, body, swept)
				draw_arc(Vector2.ZERO, filled_r, 0.0, TAU, 40, rim, 2.0)


func _arc_points(base: float, half: float, length: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	for step: int in range(ARC_STEPS + 1):
		points.append(Vector2.RIGHT.rotated(base + lerpf(-half, half, float(step) / float(ARC_STEPS))) * length)
	return points


func _sector(base: float, half: float, length: float) -> PackedVector2Array:
	var points := PackedVector2Array([Vector2.ZERO])
	points.append_array(_arc_points(base, half, length))
	return points
