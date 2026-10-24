class_name Telegraph
extends Node2D
## The ground shape that shows an enemy attack coming (SPEC-combat-core
## "Telegraph"): an outline that fills from 0 to 100% over the windup. Owned by
## combat-core. Sync: none; every peer draws it from the enemy's replicated
## `telegraph_progress` and `aim_dir`. Placeholder art: flat red shapes.

const OUTLINE_COLOR: Color = Color(1.0, 0.25, 0.2, 0.9)
const FILL_COLOR: Color = Color(1.0, 0.25, 0.2, 0.35)
const ARC_STEPS: int = 12
const OUTLINE_WIDTH: float = 1.5

var shape: AttackPattern.TelegraphShape = AttackPattern.TelegraphShape.CIRCLE
## x = length (or radius), y = width in px (cone: width in degrees).
var size: Vector2 = Vector2(48.0, 48.0)
var direction: Vector2 = Vector2.RIGHT
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


func _draw() -> void:
	if progress < 0.0:
		return
	var fill: float = clampf(progress, 0.0, 1.0)
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


func _sector(base: float, half: float, length: float) -> PackedVector2Array:
	var points := PackedVector2Array([Vector2.ZERO])
	for step: int in range(ARC_STEPS + 1):
		var angle: float = base + lerpf(-half, half, float(step) / float(ARC_STEPS))
		points.append(Vector2.RIGHT.rotated(angle) * length)
	return points
