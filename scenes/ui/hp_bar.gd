class_name HpBar
extends Control
## A framed HP bar: dark fill area, colored fill by ratio, gold frame, and a
## desaturated fill when the owner is downed. Owned by ui-hud (Dev B).
## Sync: presentation only — the ratio/is_downed values are set by the HUD
## from HudModel, which reads replicated state.

const FRAME_COLOR := Color(0.949, 0.757, 0.306) # UI palette gold
const BACKGROUND_COLOR := Color(0.169, 0.129, 0.094, 0.75) # UI palette ink
const DOWNED_TINT := Color(0.5, 0.5, 0.5)

@export var fill_color: Color = Color(0.847, 0.227, 0.227) # UI palette hp_red

var ratio: float = 1.0:
	set(value):
		ratio = clampf(value, 0.0, 1.0)
		queue_redraw()

var is_downed: bool = false:
	set(value):
		is_downed = value
		queue_redraw()


func _draw() -> void:
	var full := Rect2(Vector2.ZERO, size)
	draw_rect(full, BACKGROUND_COLOR, true)
	var fill := Rect2(Vector2(1, 1), Vector2(maxf(0.0, size.x - 2.0) * ratio, maxf(0.0, size.y - 2.0)))
	var color := fill_color
	if is_downed:
		color = color.lerp(DOWNED_TINT, 0.7)
	draw_rect(fill, color, true)
	draw_rect(full, FRAME_COLOR, false, 1.0)