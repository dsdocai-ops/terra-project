class_name Door
extends StaticBody2D
## One closed-or-open door cell of a locking room (SPEC-floor-generation
## "Doors and clearing"). Owned by floor-generation. Sync: the host decides when
## a room locks; `Floor` mirrors that to every peer so each peer's collision
## matches. Placeholder art: a brown diamond.

const WORLD_LAYER: int = 1
const CLOSED_COLOR: Color = Color(0.45, 0.3, 0.18, 1.0)

var cell: Vector2i = Vector2i.ZERO
var closed: bool = false

var _shape: CollisionShape2D = null
var _visual: Polygon2D = null


func _ready() -> void:
	var diamond: PackedVector2Array = PackedVector2Array([
		Vector2(0, -Iso.HALF_H), Vector2(Iso.HALF_W, 0),
		Vector2(0, Iso.HALF_H), Vector2(-Iso.HALF_W, 0),
	])
	_shape = CollisionShape2D.new()
	var convex := ConvexPolygonShape2D.new()
	convex.points = diamond
	_shape.shape = convex
	add_child(_shape)
	_visual = Polygon2D.new()
	_visual.polygon = diamond
	_visual.color = CLOSED_COLOR
	add_child(_visual)
	collision_layer = WORLD_LAYER
	collision_mask = 0
	set_closed(closed)


func set_closed(value: bool) -> void:
	closed = value
	if _shape == null:
		return
	_shape.set_deferred(&"disabled", not closed)
	_visual.visible = closed
