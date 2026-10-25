class_name Telegraph
extends Node2D
## The ground shape that shows an enemy attack coming (SPEC-combat-core
## "Telegraph"): an outline that fills from 0 to 100% over the windup. Owned by
## combat-core. Sync: none; every peer draws it from the enemy's replicated
## `telegraph_progress` and `aim_dir`. Placeholder art: flat red shapes.
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
	match shape:
		AttackPattern.TelegraphShape.CIRCLE:
			draw_arc(Vector2.ZERO, size.x, 0.0, TAU, 24, OUTLINE_COLOR, OUTLINE_WIDTH)
			draw_circle(Vector2.ZERO, size.x * fill, FILL_COLOR)
		AttackPattern.TelegraphShape.CONE:
			var half: float = deg_to_rad(size.y) * 0.5
			var base: float = direction.angle()
			draw_colored_polygon(_sector(base, half, size.x * fill), FILL_COLOR)
			draw_polyline(_sector(base, half, size.x) + PackedVector2Array([Vector2.ZERO]), OUTLINE_COLOR, OUTLINE_WIDTH)
		AttackPattern.TelegraphShape.LINE:
			var across: Vector2 = direction.orthogonal() * size.y * 0.5
			var far: Vector2 = direction * size.x
			var near_fill: Vector2 = direction * size.x * fill
			draw_polyline(PackedVector2Array([-across, -across + far, across + far, across, -across]), OUTLINE_COLOR, OUTLINE_WIDTH)
			draw_colored_polygon(PackedVector2Array([-across, -across + near_fill, across + near_fill, across]), FILL_COLOR)
		AttackPattern.TelegraphShape.RING:
			var ring: Dictionary = ring_geometry(size, fill)
			draw_arc(Vector2.ZERO, ring["outer"], 0.0, TAU, 32, OUTLINE_COLOR, OUTLINE_WIDTH)
			if ring["inner"] > 0.0:
				draw_arc(Vector2.ZERO, ring["inner"], 0.0, TAU, 32, OUTLINE_COLOR, OUTLINE_WIDTH)
			var swept: float = ring["filled_to"] - ring["inner"]
			if swept > 0.5:
				draw_arc(Vector2.ZERO, ring["inner"] + swept * 0.5, 0.0, TAU, 32, FILL_COLOR, swept)


func _sector(base: float, half: float, length: float) -> PackedVector2Array:
	var points := PackedVector2Array([Vector2.ZERO])
	for step: int in range(ARC_STEPS + 1):
		var angle: float = base + lerpf(-half, half, float(step) / float(ARC_STEPS))
		points.append(Vector2.RIGHT.rotated(angle) * length)
	return points
