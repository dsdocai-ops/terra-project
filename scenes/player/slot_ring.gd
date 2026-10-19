class_name SlotRing
extends Node2D
## Flat isometric ring drawn at a player's feet in the player's slot color,
## so co-op players are easy to tell apart whatever their sprite looks like.
## Owned by player-controller. Sync: none, every peer draws it from the
## replicated Player.slot.

const RADIUS := 11.0
const LINE_WIDTH := 2.0
const FILL_ALPHA := 0.25
## Ground plane squash: iso tiles are twice as wide as they are tall.
const ISO_SQUASH := Vector2(1.0, 0.5)

var color: Color = Color.WHITE:
	set(value):
		if value == color:
			return
		color = value
		queue_redraw()


func _draw() -> void:
	draw_set_transform(Vector2.ZERO, 0.0, ISO_SQUASH)
	draw_circle(Vector2.ZERO, RADIUS, Color(color, FILL_ALPHA))
	draw_arc(Vector2.ZERO, RADIUS, 0.0, TAU, 32, color, LINE_WIDTH)
