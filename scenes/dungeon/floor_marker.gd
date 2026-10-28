class_name FloorMarker
extends Node2D
## One placeholder marker of a special room (W3-A2): START, EXIT or ROPE.
## Owned by floor-generation. Sync: none — every peer builds the same markers
## from the same layout. Placeholder art: a colored diamond and its label, the
## Door pattern; W3-A6 replaces these with real sprites.

const START_COLOR: Color = Color(0.3, 0.85, 0.4, 1.0)
const EXIT_COLOR: Color = Color(0.9, 0.35, 0.25, 1.0)
const ROPE_COLOR: Color = Color(0.35, 0.7, 0.95, 1.0)
const LABEL_SCALE: float = 0.5

## A `FloorGenerator.RoomType` value; only START, EXIT and ROPE are marked.
var kind: int = FloorGenerator.RoomType.START

var _visual: Polygon2D = null


## The placeholder color of `p_kind`'s marker.
static func color_for(p_kind: int) -> Color:
	match p_kind:
		FloorGenerator.RoomType.EXIT:
			return EXIT_COLOR
		FloorGenerator.RoomType.ROPE:
			return ROPE_COLOR
		_:
			return START_COLOR


## Call before the marker enters the tree.
func setup(p_kind: int) -> void:
	kind = p_kind
	name = "Marker_%s" % text()


## The placeholder's text: START, EXIT or ROPE.
func text() -> String:
	match kind:
		FloorGenerator.RoomType.EXIT:
			return "EXIT"
		FloorGenerator.RoomType.ROPE:
			return "ROPE"
		_:
			return "START"


func _ready() -> void:
	var diamond: PackedVector2Array = PackedVector2Array([
		Vector2(0, -Iso.HALF_H), Vector2(Iso.HALF_W, 0),
		Vector2(0, Iso.HALF_H), Vector2(-Iso.HALF_W, 0),
	])
	_visual = Polygon2D.new()
	_visual.polygon = diamond
	_visual.color = color_for(kind)
	add_child(_visual)
	var caption := Label.new()
	caption.text = text()
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.position = Vector2(-Iso.HALF_W, Iso.HALF_H)
	caption.scale = Vector2(LABEL_SCALE, LABEL_SCALE)
	add_child(caption)
